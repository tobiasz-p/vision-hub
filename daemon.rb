#!/usr/bin/env ruby
# frozen_string_literal: true

# VisionHub daemon entry point. Runs inside the plugin's long-lived shell
# process context (launched by the QML service layer) and owns every ffmpeg
# child, so decoders never execute in-process with Quickshell.
#
# Protocol: JSON lines on stdin/stdout (see lib/vision_hub/ipc.rb). EOF on
# stdin — or our own death — takes all children down with us.

require 'optparse'
require_relative 'lib/vision_hub'

options = {
  fps: 5,
  main_fps: 15,
  hwaccel: true,
  input_strategy: :argv,
  probe_interval: VisionHub::Supervisor::DEFAULT_PROBE_INTERVAL
}
parser = OptionParser.new do |opts|
  opts.banner = 'Usage: daemon.rb --config PATH --runtime-dir DIR [options]'
  opts.on('--config PATH', 'cameras.json path') { |v| options[:config] = v }
  opts.on('--runtime-dir DIR', 'tmpfs directory for frames and playlists') { |v| options[:runtime_dir] = v }
  opts.on('--fps N', Integer, 'sub-stream target fps') { |v| options[:fps] = v }
  opts.on('--main-fps N', Integer, 'focused-stream target fps') { |v| options[:main_fps] = v }
  opts.on('--no-hwaccel', 'disable hardware decode') { options[:hwaccel] = false }
  opts.on('--input STRATEGY', %w[argv concat_file], 'credential delivery strategy') do |v|
    options[:input_strategy] = v.to_sym
  end
end
parser.parse(ARGV)

abort('missing --config') unless options[:config]
abort('missing --runtime-dir') unless options[:runtime_dir]

config = VisionHub::Configuration.load(options[:config])
unless config.ok?
  warn "vision-hub: config error: #{config.error}"
  exit 65
end

# Minimal stderr JSON-lines logger; :debug is compiled out so the pipe to the
# shell never carries chatter.
logger = Class.new do
  %i[info warn error].each do |level|
    define_method(level) { |message| warn({ ts: VisionHub::Clock.now.round(3), level: level, msg: message }.to_json) }
  end

  def debug(_message) = nil
end.new

supervisor = VisionHub::Supervisor.new(
  cameras: config.active_cameras,
  runtime_dir: options[:runtime_dir],
  secrets: VisionHub::SecretStore.new(application_id: 'tobiasz-p.vision-hub'),
  fps: options[:fps],
  main_fps: options[:main_fps],
  hwaccel: options[:hwaccel],
  input_strategy: options[:input_strategy],
  probe_interval: options[:probe_interval],
  logger: logger
)
reader = VisionHub::Ipc::Reader.new

def flush_events(supervisor)
  supervisor.drain_outbox.each { |event| $stdout.write(VisionHub::Ipc.encode(event)) }
  $stdout.flush
rescue Errno::EPIPE
  nil
end

begin
  supervisor.start(now: VisionHub::Clock.now)
  flush_events(supervisor)

  loop do
    if $stdin.wait_readable(0.25)
      begin
        chunk = $stdin.read_nonblock(4096)
        reader.feed(chunk).each do |result|
          if result.kind == :message
            supervisor.handle(result.message, now: VisionHub::Clock.now)
          else
            warn "vision-hub: dropped #{result.kind} stdin line: #{result.detail}"
          end
        end
      rescue IO::WaitReadable, Errno::EAGAIN
        nil
      rescue EOFError
        break
      end
    end
    supervisor.tick(now: VisionHub::Clock.now)
    flush_events(supervisor)
  end
ensure
  # Grace period for TERM; PDEATHSIG covers anything we fail to reap.
  supervisor&.shutdown(now: VisionHub::Clock.now)
  deadline = VisionHub::Clock.now + VisionHub::FramePump::STOP_GRACE
  while VisionHub::Clock.now < deadline
    supervisor&.tick(now: VisionHub::Clock.now)
    sleep 0.1
  end
end
