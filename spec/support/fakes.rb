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
      @events << [:start, now]
      case @start_mode
      when :unconfigured then fire(event: :unconfigured)
      else
        @running = true
        fire(event: :started)
      end
    end

    def stop(now:, immediate: false)
      @running = false
      @events << [:stop, now, immediate]
      fire(event: :exited, code: 0, intentional: true, error: nil)
    end

    def tick(now:) = @events << [:tick, now]

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
end
