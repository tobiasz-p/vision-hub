# frozen_string_literal: true

module VisionHub
  # Supervises exactly one ffmpeg child that pulls an RTSP stream and writes
  # continuously-overwritten JPEG frames into tmpfs.
  #
  # The pump is deliberately dumb about scheduling: the daemon calls tick(now)
  # from its event loop and passes the time in, which keeps the whole state
  # machine deterministic and testable with fake processes.
  #
  # Credential handling: the RTSP URL is assembled in memory only. With the
  # default :argv strategy ffmpeg receives it on its command line — a known,
  # documented exposure (see design §7). The :concat_file strategy hands
  # ffmpeg a mode-0600 playlist instead; whether it survives contact with real
  # cameras is exactly what the spike phase decides.
  class FramePump
    ROLES = %i[sub main].freeze
    BACKOFF_INITIAL = 1.0
    BACKOFF_MAX = 60.0
    STABLE_AFTER = 30.0
    STOP_GRACE = 2.0
    KILL_GRACE = 1.0
    UNCONFIGURED_RETRY = 30.0
    RTSP_TIMEOUT_US = 8_000_000

    attr_reader :camera, :role, :fps, :hwaccel, :input_strategy, :status, :last_error

    def initialize(camera:, role:, runtime_dir:, fps:, hwaccel:,
                   input_strategy: :argv, secrets: nil, logger: nil,
                   spawner: ChildProcess.method(:spawn),
                   reaper: ChildProcess.method(:reap), killer: ChildProcess.method(:kill))
      raise ArgumentError, "unknown role #{role.inspect}" unless ROLES.include?(role)

      @camera = camera
      @role = role
      @runtime_dir = runtime_dir
      @fps = fps
      @hwaccel = hwaccel
      @input_strategy = input_strategy
      @secrets = secrets
      @logger = logger
      @spawner = spawner
      @reaper = reaper
      @killer = killer
      reset_process_state
      @wanted = false
    end

    def running?
      !@pid.nil? && status == :running
    end

    def wanted?
      @wanted
    end

    def frame_path
      File.join(@runtime_dir, "#{@camera.id}.jpg")
    end

    def on_event(&block)
      @on_event = block
      self
    end

    # ---- control ----

    def start(now: Clock.now)
      @wanted = true
      # Backoff and in-flight stops are owned by tick(); spawning over them
      # would defeat the retry schedule.
      return if %i[running stopping backoff].include?(status)

      @attempts = 0 if %i[idle stopped].include?(status)
      attempt_spawn(now)
    end

    # Marked unwanted; actual teardown happens across ticks so the event loop
    # never blocks longer than one signal send.
    def stop(now: Clock.now)
      @wanted = false
      @next_action_at = nil
      return unless @pid

      @status = :stopping
      @stop_deadline = now + STOP_GRACE
      signal('TERM')
    end

    def tick(now: Clock.now)
      reap_child(now) if @pid
      drain_stderr if @stderr_io
      case status
      when :stopping then advance_stop(now)
      when :backoff, :unconfigured then attempt_spawn(now) if @next_action_at && now >= @next_action_at
      end
      check_stability(now)
      drop_stale_playlist
    end

    # ---- argv construction (exposed for specs and the spike) ----

    def build_argv(url)
      argv = ['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'warning']
      argv += ['-hwaccel', 'auto'] if @hwaccel
      argv += input_argv(url)
      if @role == :sub
        argv + ['-an', '-sn', '-dn', '-vf', 'scale=640:-1', '-frames:v', '1', '-q:v', '6', '-y', frame_path]
      else
        argv + ['-an', '-sn', '-dn', '-vf', "fps=#{@fps},scale=1280:-1", '-q:v', '6', '-update', '1',
                '-y', frame_path]
      end
    end

    private

    def input_argv(url)
      case @input_strategy
      when :argv
        ['-rtsp_transport', 'tcp', '-timeout', FramePump::RTSP_TIMEOUT_US.to_s, '-i', url]
      when :concat_file
        write_playlist(url)
        ['-f', 'concat', '-safe', '0', '-i', playlist_path]
      else
        raise ArgumentError, "unknown input strategy #{@input_strategy.inspect}"
      end
    end

    def reset_process_state
      @pid = nil
      @stderr_io = nil
      @stderr_tail = +''
      @status = :idle
      @attempts = 0
      @next_action_at = nil
      @started_at = nil
      @stop_deadline = nil
      @kill_deadline = nil
      @last_error = nil
    end

    # ---- lifecycle transitions ----

    def attempt_spawn(now)
      password = lookup_password
      if password.nil? && @camera.wants_password?
        mark_unconfigured(now)
        return
      end

      spawn_child(build_argv(build_url(password)), now)
    rescue StandardError => e
      @status = :backoff
      schedule_retry(now)
      @last_error = "#{e.class}: #{e.message}"
      emit(event: :spawn_failed, error: @last_error)
    end

    def mark_unconfigured(now)
      @status = :unconfigured
      @next_action_at = now + UNCONFIGURED_RETRY
      emit(event: :unconfigured)
    end

    def lookup_password
      return nil unless @camera.wants_password?

      pw = @secrets&.lookup(@camera.id)
      @last_error = nil if pw
      pw
    end

    def build_url(password)
      return @camera.mainstream_url(password) if role == :main

      @camera.substream_url(password)
    end

    def spawn_child(argv, now)
      @pid, @stderr_io = @spawner.call(argv)
      @stderr_tail.clear
      @status = :running
      @started_at = now
      @stop_deadline = nil
      @kill_deadline = nil
      @next_action_at = nil
      log(:debug, "spawned pid #{@pid} (#{role})")
      emit(event: :started)
    end

    def reap_child(now)
      result = @reaper.call(@pid, Process::WNOHANG)
      return unless result

      _pid, process_status = result
      finish_child(process_status, now, intentional: status == :stopping)
    end

    def finish_child(process_status, now, intentional:)
      exit_code = process_status.respond_to?(:exitstatus) ? process_status.exitstatus : process_status.to_i
      log(:info, "pid #{@pid} exited code #{exit_code} (#{intentional ? 'stopped' : 'died'})")
      if intentional
        finish_intentional(exit_code, now)
      elsif @role == :sub && exit_code.zero?
        close_child
        @status = :stopped
        emit(event: :exited, code: exit_code, intentional: true, error: nil)
      else
        finish_crashed(exit_code, now)
      end
    end

    # Child answered our TERM (or was reaped during shutdown). Restart only if
    # someone called start() again meanwhile.
    def finish_intentional(exit_code, now)
      close_child
      @status = @wanted ? :backoff : :stopped
      schedule_retry(now) if @wanted
      emit(event: :exited, code: exit_code, intentional: true, error: nil)
    end

    # Unexpected death: harvest stderr for the reason, count the attempt.
    def finish_crashed(exit_code, now)
      detail = newest_stderr_line
      close_child
      @attempts += 1
      @last_error = compose_error(exit_code, detail) if detail
      @status = :backoff
      schedule_retry(now)
      emit(event: :exited, code: exit_code, intentional: false, error: @last_error)
    end

    def compose_error(exit_code, detail)
      prefix = "ffmpeg exited with code #{exit_code}"
      detail ? "#{prefix}: #{detail}" : prefix
    end

    def schedule_retry(now)
      delay = [BACKOFF_INITIAL * (2**(@attempts - 1)), BACKOFF_MAX].min
      @next_action_at = now + delay
    end

    def advance_stop(now)
      deadline = @kill_deadline || @stop_deadline
      return unless @pid && now >= deadline

      if @kill_deadline.nil?
        log(:warn, "pid #{@pid} ignored TERM; sending KILL")
        signal('KILL')
        @kill_deadline = now + KILL_GRACE
      else
        log(:warn, "pid #{@pid} unkillable; abandoning wait")
        close_child
        @status = :stopped
        emit(event: :exited, code: nil, intentional: true, error: nil)
      end
    end

    def check_stability(now)
      return unless status == :running && @started_at && now - @started_at >= STABLE_AFTER

      @attempts = 0
    end

    def drop_stale_playlist
      return if @input_strategy != :concat_file || running?

      require 'fileutils'
      FileUtils.rm_f(playlist_path)
    rescue StandardError => e
      log(:debug, "playlist cleanup failed: #{e.message}")
    end

    def close_child
      @pid = nil
      @stderr_io&.close
      @stderr_io = nil
      @started_at = nil
      @stop_deadline = nil
      @kill_deadline = nil
    end

    def signal(name)
      return true if @killer.call(-@pid, name)

      @killer.call(@pid, name)
    end

    # ---- stderr capture ----

    def drain_stderr
      loop do
        chunk = @stderr_io&.read_nonblock(4096)
        break if chunk.nil?

        @stderr_tail << chunk
        keep_last_lines
      end
    rescue IO::WaitReadable, Errno::EAGAIN, EOFError
      nil
    end

    def keep_last_lines
      lines = @stderr_tail.lines
      @stderr_tail = +''
      lines.last(4).each { |line| @stderr_tail << line }
    end

    def newest_stderr_line
      drain_stderr
      line = @stderr_tail.lines.last&.strip
      line.to_s.empty? ? nil : line
    end

    # ---- playlist (:concat_file strategy) ----

    def playlist_path
      File.join(@runtime_dir, "#{@camera.id}.#{role}.ffconcat")
    end

    def write_playlist(url)
      escaped = url.gsub("'", "''")
      content = "ffconcat version 1.0\nfile '#{escaped}'\n"
      File.open(playlist_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(content) }
    end

    # ---- plumbing ----

    def emit(payload)
      return unless @on_event

      @on_event.call({ camera: @camera.id, role: role }.merge(payload))
    end

    def log(level, message)
      @logger&.public_send(level, "[pump #{@camera.id}/#{role}] #{message}")
    end
  end
end
