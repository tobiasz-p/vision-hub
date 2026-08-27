# frozen_string_literal: true

RSpec::Matchers.define :have_file_mode do |expected_mode|
  match do |file_path|
    actual_mode = format("%o", File.stat(file_path).mode)
    actual_mode.end_with?(expected_mode.to_s)
  end

  failure_message do |file_path|
    actual_mode = format("%o", File.stat(file_path).mode)
    "expected #{file_path} to have file mode #{expected_mode}, but got #{actual_mode}"
  end
end
