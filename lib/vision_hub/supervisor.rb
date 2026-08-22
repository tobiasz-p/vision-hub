# frozen_string_literal: true

require_relative 'audio_pump'

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
      init_collaborators(collaborators)
      reset_state
    end

    def init_collaborators(collaborators)
      @build_pump = collaborators[:build_pump] || ->(kwargs) { FramePump.new(**kwargs) }
      @audio_pump_builder = collaborators[:audio_pump_builder] || ->(kwargs) { AudioPump.new(**kwargs) }
      @probe_runner = collaborators[:probe_runner] || ->(camera) { HealthProbe.new.probe(camera.host, camera.port) }
    end

    def reset_state
      @audio_pump = nil
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
      @states = @cameras.to_h { |c| [c.id, { id: c.id, online: nil, streaming: false, error: nil }] }
      @pumps = @cameras.to_h { |c| [c.id, { sub: new_pump(c, :sub), main: nil }] }
      @pumps.each_value { |entry| entry[:sub].start(now: now) }
      emit(:hello, cameras: @cameras.map(&:id))
      @ready = true
      publish_changes
    end

    # ---- IPC commands ----

    def handle(message, now:)
      @now = now
      case message['cmd']
      when 'ping' then emit(:pong, echo: message['echo'])
      when 'refresh' then refresh_all
      when 'focus' then handle_focus_cmd(message)
      when 'unfocus' then unfocus
      when 'set_fps' then change_fps(message['fps'])
      when 'audio' then handle_audio_cmd(message)
      else emit(:error, message: "unknown command #{message['cmd'].inspect}")
      end
    end

    def handle_focus_cmd(message)
      focus(message['camera'], fps: message['fps']&.to_i)
    end

    def handle_audio_cmd(message)
      toggle_audio(message['camera'], message['enabled'] == true)
    end

    def tick(now:)
      return unless ready?

      @now = now
      run_due_probe
      each_pump { |pump| pump.tick(now: @now) }
      @audio_pump&.tick(now: @now)
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
      stop_audio
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

    def new_pump(camera, role, fps: nil)
      @build_pump.call(
        camera: camera, role: role, runtime_dir: @runtime_dir,
        fps: role == :main ? (fps || @main_fps) : @fps,
        hwaccel: @hwaccel,
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

    def run_due_probe
      id = @round_robin.next
      return if @now < @probe_due[id]

      @probe_due[id] = @now + @probe_interval
      camera = @cameras.find { |c| c.id == id }
      result = @probe_runner.call(camera)
      was_online = @states[id][:online]
      @states[id][:online] = result == :online
      publish_changes if was_online != @states[id][:online]
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
      @probe_due[camera.id] = @now + @probe_interval
      publish_changes if was_online != @states[camera.id][:online]
      @pumps.dig(camera.id, :sub)&.start(now: @now) if result == :online
    end

    # ---- focus ----

    def focus(camera_id, fps: nil)
      camera = @cameras.find { |c| c.id == camera_id }
      return emit(:error, message: "focus: unknown camera #{camera_id.inspect}") unless camera

      target_fps = fps || @main_fps
      return if matching_focus?(camera_id, target_fps)

      unfocus(immediate: true)
      @focused_id = camera_id
      main = new_pump(camera, :main, fps: target_fps)
      @pumps[camera_id][:main] = main
      main.start(now: @now)
    end

    def matching_focus?(camera_id, target_fps)
      current = @pumps.dig(camera_id, :main)
      @focused_id == camera_id && current&.running? && current.fps == target_fps
    end

    def change_fps(fps)
      @main_fps = fps.to_i if fps&.to_i&.positive?
      focus(@focused_id, fps: @main_fps) if @focused_id
    end

    def unfocus(immediate: false)
      stop_audio
      return unless @focused_id

      entry = @pumps[@focused_id]
      entry[:main]&.stop(now: @now, immediate: immediate)
      entry[:main] = nil
      @focused_id = nil
    end

    def toggle_audio(camera_id, enabled)
      stop_audio
      return unless enabled

      camera = @cameras.find { |c| c.id == (camera_id || @focused_id) }
      return unless camera

      @audio_pump = @audio_pump_builder.call(camera: camera, secrets: @secrets, logger: @logger)
      @audio_pump.start(now: @now)
    end

    def stop_audio
      @audio_pump&.stop(now: @now)
      @audio_pump = nil
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
