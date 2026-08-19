# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'vision_hub'
require_relative 'support/fakes'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
end

# Ruby 4 made IO::WaitWritable a Module and moved the raisable exceptions to
# IO::EWOULDBLOCKWaitWritable / IO::EINPROGRESSWaitReadable-style classes.
# Test doubles need a class they can actually raise.
WAIT_WRITABLE = IO::WaitWritable.is_a?(Class) ? IO::WaitWritable : IO::EWOULDBLOCKWaitWritable
WAIT_READABLE = IO::WaitReadable.is_a?(Class) ? IO::WaitReadable : IO::EWOULDBLOCKWaitReadable
