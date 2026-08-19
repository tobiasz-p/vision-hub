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
                   probe_interval: DEFAULT_PROBE_INTERVAL, logger: nil,
                   build_pump: nil, probe_runner: nil)
      @cameras = cameras
      @runtime_dir = runtime_dir
      @secrets = secrets
      @fps = fps
      @main_fps = main_fps
      @hwaccel = hwaccel
      @input_strategy = input_strategy
      @probe_interval = probe_interval
      @logger = logger
      @build_pump = build_pump || ->(kwargs) { FramePump.new(**kwargs) }
      @probe_runner = probe_runner || ->(camera) { HealthProbe.new.probe(camera.host, camera.port) }
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
      when 'focus' then focus(message['camera'])
      when 'unfocus' then unfocus
      else emit(:error, message: "unknown command #{message['cmd'].inspect}")
      end
    end

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

    def new_pump(camera, role)
      @build_pump.call(
        camera: camera, role: role, runtime_dir: @runtime_dir,
        fps: role == :main ? @main_fps : @fps, hwaccel: @hwaccel,
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
      @cameras.each do |camera|
        result = @probe_runner.call(camera)
        was_online = @states[camera.id][:online]
        @states[camera.id][:online] = result == :online
        @probe_due[camera.id] = @now + @probe_interval
        publish_changes if was_online != @states[camera.id][:online]
      end
      publish_changes
    end

    # ---- focus ----

    def focus(camera_id)
      camera = @cameras.find { |c| c.id == camera_id }
      unless camera
        emit(:error, message: "focus: unknown camera #{camera_id.inspect}")
        return
      end

      current = @pumps.dig(camera_id, :main)
      return if @focused_id == camera_id && current&.running?

      unfocus
      @focused_id = camera_id
      main = current || new_pump(camera, :main)
      @pumps[camera_id][:main] = main
      main.start(now: @now)
    end

    def unfocus
      return unless @focused_id

      entry = @pumps[@focused_id]
      entry[:main]&.stop(now: @now)
      entry[:main] = nil
      @focused_id = nil
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
