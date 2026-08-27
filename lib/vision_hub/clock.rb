# frozen_string_literal: true

module VisionHub
  # Monotonic clock indirection so every component takes `now` arguments that
  # specs control directly.
  module Clock
    # Returns the current monotonic clock reading in seconds.
    #
    # @return [Float] current monotonic timestamp in seconds
    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
