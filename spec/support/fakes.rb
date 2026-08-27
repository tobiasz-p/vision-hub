# frozen_string_literal: true

# Shared test doubles for process-adjacent collaborators. Kept outside spec
# files so multiple suites can require them without constant-in-block lint.
module Fakes
  # Minimal stand-in matching VisionHub::SecretStore#lookup. The table is held
  # by reference so tests can reveal credentials mid-scenario.
  class Secrets
    def initialize(table = {})
      @table = table
    end

    def lookup(camera_id)
      @table[camera_id]
    end

    def reveal!(camera_id, password)
      @table[camera_id] = password
    end
  end

  # Controllable FramePump double for Supervisor specs. start_mode switches
  # what a start() call reports; fail_later/unconfigure_later inject events.
  class Pump
    attr_reader :kwargs, :events
    attr_accessor :start_mode

    def initialize(kwargs)
      @kwargs = kwargs
      @running = false
      @events = []
      @start_mode = :ok
    end

    def on_event(&block)
      @callback = block
      self
    end

    def start(now:)
      events << [:start, now]
      case start_mode
      when :unconfigured then fire(event: :unconfigured)
      else
        @running = true
        fire(event: :started)
      end
    end

    def stop(now:, immediate: false)
      @running = false
      events << [:stop, now, immediate]
      fire(event: :exited, code: 0, intentional: true, error: nil)
    end

    def tick(now:) = events << [:tick, now]

    def running? = @running

    def status = @running ? :running : :idle

    def fps = @kwargs[:fps]

    def audio = @kwargs[:audio] || false

    def quality = @kwargs[:quality]

    def last_error = nil

    def fail_later(error)
      @running = false
      fire(event: :exited, code: 255, intentional: false, error:)
    end

    def unconfigure_later
      fire(event: :unconfigured)
    end

    private

    def fire(payload)
      @events << payload
      @callback&.call({ camera: kwargs[:camera].id, role: kwargs[:role] }.merge(payload))
    end
  end

  # Stand-in for Process::Status carrying just the exit code the pump reads.
  Status = Struct.new(:exitstatus) do
    def to_i = exitstatus
  end

  # Test harness for simulating process spawn, waitpid, and signal delivery.
  class ProcessHarness
    attr_reader :spawned, :live, :signals, :exits
    attr_accessor :spawn_stderr

    def initialize
      @spawned = []
      @live = {}
      @signals = []
      @exits = {}
      @pid_counter = 4000
      @spawn_stderr = ""
    end

    def last_pid
      @pid_counter
    end

    def spawner
      lambda do |argv|
        @pid_counter += 1
        pid = @pid_counter
        @spawned << argv.dup
        @live[pid] = true
        [pid, StringIO.new(@spawn_stderr.dup)]
      end
    end

    def reaper
      lambda do |pid, _flags|
        return nil unless @exits.key?(pid)

        code = @exits.delete(pid)
        @live.delete(pid)
        [pid, Status.new(code)]
      end
    end

    def killer
      lambda do |target, name|
        @signals << [target, name]
        @live.key?(target.abs)
      end
    end
  end

  # Fake socket that raises WAIT_WRITABLE for non-blocking timeout testing.
  class NonWritableSocket
    def initialize(*); end

    def connect_nonblock(_address)
      raise WAIT_WRITABLE
    end

    def close; end
  end

  # Fake socket that simulates EINPROGRESS handshake (refuses first, succeeds second).
  class RetryingSocket < NonWritableSocket
    def connect_nonblock(_address)
      @tries ||= 0
      @tries += 1
      raise WAIT_WRITABLE if @tries == 1

      :ok
    end
  end
end
