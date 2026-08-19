# frozen_string_literal: true

module VisionHub
  # Monotonic clock indirection so every component takes `now` arguments that
  # specs control directly.
  module Clock
    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
