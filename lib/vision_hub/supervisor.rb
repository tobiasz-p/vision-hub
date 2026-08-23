# frozen_string_literal: true

module VisionHub
  # Orchestrates health probes and frame pumps for every configured camera,
  # translates IPC commands into lifecycle actions, and emits state events.
  #
  # Like FramePump, the supervisor never reads the wall clock itself: the
  # daemon's event loop calls the public methods with time injected, keeping
  # behavior deterministic under specs. All collaborators (probe runner, pump
  # builder) are injectable so tests run entirely on fakes.
  #
  # Probes deliberately run one camera per tick, round-robin: a probe against
  # an unreachable host blocks up to its connect timeout inside select(), and
  # staggering keeps any single tick's stall bounded while ffmpeg children —
  # which own the actual video path — keep running unaffected.
  class Supervisor
    DEFAULT_PROBE_INTERVAL = 10.0

    def initialize(cameras:, runtime_dir:, secrets:,
                   fps:, main_fps:, hwaccel:, input_strategy:,
                   probe_interval: DEFAULT_PROBE_INTERVAL, logger: nil, **collaborators)
      @cameras = cameras
      @runtime_dir = runtime_dir
      @secrets = secrets
      @fps = fps
      @main_fps = main_fps
      @hwaccel = hwaccel
      @input_strategy = input_strategy
      @probe_interval = probe_interval
      @logger = logger
      @build_pump = collaborators[:build_pump] || ->(kwargs) { FramePump.new(**kwargs) }
      @probe_runner = collaborators[:probe_runner] || ->(camera) { HealthProbe.new.probe(camera.host, camera.port) }
      @audio_enabled = false
      @window_open = false
      @outbox = []
      @focused_id = nil
      @last_emitted = {}
      # Nothing is published until start() has queued hello, so the shell's
      # first sight of camera states always follows session metadata.
      @ready = false
    end

    def start(now:)
      @now = now
      @probe_due = Hash.new(0.0)
      @round_robin = @cameras.map(&:id).cycle
      @states = @cameras.to_h { |c| [c.id, { id: c.id, name: c.name, online: nil, streaming: false, error: nil }] }
      @pumps = @cameras.to_h { |c| [c.id, { sub: new_pump(c, :sub), main: nil }] }
      @pumps.each_value { |entry| entry[:sub].start(now: now) }
      emit(:hello, cameras: @cameras.map(&:id))
      @ready = true
      publish_changes
    end

    COMMAND_HANDLERS = {
      'ping' => :handle_ping,
      'refresh' => :handle_refresh,
      'focus' => :handle_focus,
      'unfocus' => :handle_unfocus,
      'set_fps' => :handle_fps,
      'audio' => :handle_audio,
      'window' => :handle_window
    }.freeze

    # ---- IPC commands ----

    def handle(message, now:)
      @now = now
      cmd = message['cmd']
      method = COMMAND_HANDLERS[cmd]
      return send(method, message) if method

      emit(:error, message: "unknown command #{cmd.inspect}")
    end

    def handle_ping(message) = emit(:pong, echo: message['echo'])
    def handle_refresh(_msg) = refresh_all
    def handle_focus(message) = focus(message['camera'], fps: message['fps']&.to_i, audio: message['audio'])
    def handle_unfocus(_msg) = unfocus
    def handle_fps(message) = change_fps(message['fps'])
    def handle_audio(message) = toggle_audio(message['camera'], message['enabled'] == true)
    def handle_window(message) = update_window_state(message['open'] == true)

    def tick(now:)
      return unless ready?

      @now = now
      run_due_probe
      each_pump { |pump| pump.tick(now: @now) }
      publish_changes
    end

    def drain_outbox
      events = @outbox.dup
      @outbox.clear
      events
    end

    # Best-effort teardown when the daemon exits: every pump gets TERM now;
    # the caller escalates via further ticks or relies on PDEATHSIG if this
    # process is killed outright.
    def shutdown(now:)
      return unless @pumps

      each_pump { |pump| pump.stop(now: now) }
    end

    private

    def ready?
      @ready && !@states.nil?
    end

    def each_pump
      @pumps.each_value do |entry|
        yield entry[:sub] if entry[:sub]
        yield entry[:main] if entry[:main]
      end
    end

    def new_pump(camera, role, fps: nil, audio: false)
      @build_pump.call(
        camera: camera, role: role, runtime_dir: @runtime_dir,
        fps: role == :main ? (fps || @main_fps) : @fps,
        hwaccel: @hwaccel,
        audio: role == :main ? audio : false,
        input_strategy: @input_strategy, secrets: @secrets
      ).on_event { |payload| absorb_pump_event(payload) }
    end

    # Pump callbacks fire synchronously inside our own tick/handle, so @now is
    # already the current virtual time.
    def absorb_pump_event(payload)
      id = payload[:camera]
      state = @states[id]
      case payload[:event]
      when :started
        state[:streaming] = true
      when :exited
        entry = @pumps[id]
        state[:streaming] = [entry[:sub], entry[:main]].compact.any?(&:running?)
      end
      state[:error] =
        if payload[:event] == :unconfigured
          'credentials not found in keyring'
        else
          payload[:error]
        end
      publish_changes
    end

    # ---- probing ----

    def current_probe_interval
      @window_open && !@focused_id ? 1.0 : @probe_interval
    end

    def run_due_probe
      id = @round_robin.next
      return if @now < @probe_due[id]

      camera = @cameras.find { |c| c.id == id }
      refresh_camera(camera) if camera
    rescue StopIteration
      nil
    end

    def refresh_all
      @cameras.each { |camera| refresh_camera(camera) }
      publish_changes
    end

    def refresh_camera(camera)
      result = @probe_runner.call(camera)
      was_online = @states[camera.id][:online]
      @states[camera.id][:online] = result == :online
      @probe_due[camera.id] = @now + current_probe_interval
      publish_changes if was_online != @states[camera.id][:online]
      @pumps.dig(camera.id, :sub)&.start(now: @now) if result == :online && @window_open && !@focused_id
    end

    # ---- window and focus control ----

    def update_window_state(open)
      @window_open = open
      if @window_open
        resume_grid_pumps unless @focused_id
      else
        stop_all_streaming
      end
    end

    def resume_grid_pumps
      @pumps.each_value { |entry| entry[:sub]&.start(now: @now) }
    end

    def stop_all_streaming
      unfocus(immediate: true)
      @pumps.each_value { |entry| entry[:sub]&.stop(now: @now, immediate: true) }
    end

    def focus(camera_id, fps: nil, audio: nil)
      camera = @cameras.find { |c| c.id == camera_id }
      return emit(:error, message: "focus: unknown camera #{camera_id.inspect}") unless camera

      target_fps = fps || @main_fps
      target_audio = audio.nil? ? @audio_enabled : audio
      return if matching_focus?(camera_id, target_fps, target_audio)

      start_focus(camera, target_fps, target_audio)
    end

    def start_focus(camera, target_fps, target_audio)
      stop_current_focus(immediate: true)
      @focused_id = camera.id
      @pumps[camera.id][:sub]&.stop(now: @now, immediate: true)
      main = new_pump(camera, :main, fps: target_fps, audio: target_audio)
      @pumps[camera.id][:main] = main
      main.start(now: @now)
    end

    def stop_current_focus(immediate: false)
      return unless @focused_id

      prev_id = @focused_id
      @audio_enabled = false
      entry = @pumps[prev_id]
      entry[:main]&.stop(now: @now, immediate: immediate)
      entry[:main] = nil
      @focused_id = nil
      entry[:sub]&.start(now: @now) if @window_open
    end

    def matching_focus?(camera_id, target_fps, target_audio)
      current = @pumps.dig(camera_id, :main)
      @focused_id == camera_id && current&.running? &&
        current.fps == target_fps && current.audio == target_audio
    end

    def change_fps(fps)
      @main_fps = fps.to_i if fps&.to_i&.positive?
      focus(@focused_id, fps: @main_fps) if @focused_id
    end

    def toggle_audio(camera_id, enabled)
      @audio_enabled = enabled
      focus(camera_id || @focused_id, audio: @audio_enabled) if @focused_id
    end

    def unfocus(immediate: false)
      stop_current_focus(immediate: immediate)
    end

    # ---- state publication ----

    # Emits camera_state only for cameras whose observable state actually
    # changed, so a quiet system produces no traffic toward the shell.
    def publish_changes
      return unless @ready

      @states.each_key do |id|
        current = compute_state(id)
        next if @last_emitted[id] == current

        @last_emitted[id] = current
        emit(:camera_state, **current)
      end
    end

    def compute_state(id)
      entry = @pumps.fetch(id, {})
      {
        id: id,
        online: @states[id][:online],
        streaming: [entry[:sub], entry[:main]].compact.any?(&:running?),
        error: @states[id][:error]
      }
    end

    def emit(event, **payload)
      @outbox << { event: event }.merge(payload)
      log(:debug, "emit #{event} #{payload.inspect}")
    end

    def log(level, message)
      @logger&.public_send(level, "[supervisor] #{message}")
    end
  end
end
