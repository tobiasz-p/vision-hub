# frozen_string_literal: true

require_relative 'child_process'
require_relative 'clock'

module VisionHub
  # Manages an isolated child process playing the camera's RTSP audio track
  # (e.g. ffplay) with clean lifecycle control and crash isolation.
  class AudioPump
    attr_reader :camera, :status, :last_error

    def initialize(camera:, secrets: nil, logger: nil, **process_io)
      @camera = camera
      @secrets = secrets
      @logger = logger
      @spawner = process_io[:spawner] || ChildProcess.method(:spawn)
      @reaper = process_io[:reaper] || ChildProcess.method(:reap)
      @killer = process_io[:killer] || ChildProcess.method(:kill)
      @status = :idle
      @pid = nil
      @on_event = nil
    end

    def running?
      !@pid.nil? && @status == :running
    end

    def on_event(&block)
      @on_event = block
      self
    end

    def start(*)
      return if running?

      password = @secrets&.lookup(@camera.id)
      if @camera.wants_password? && password.nil?
        @status = :unconfigured
        fire(event: :unconfigured)
        return
      end

      url = @camera.mainstream_url(password)
      argv = build_argv(url)
      @pid = @spawner.call(argv)
      @status = :running
      fire(event: :started)
    rescue StandardError => e
      @status = :idle
      @last_error = e.message
      fire(event: :error, message: e.message)
    end

    def stop(*)
      return unless @pid

      target = @pid
      @pid = nil
      @status = :idle
      @killer.call(-target, 'TERM')
      @reaper.call(target, false)
      fire(event: :stopped)
    end

    def tick(*)
      return unless @pid

      reaped_pid, exit_status = @reaper.call(@pid, false)
      return unless reaped_pid

      @pid = nil
      @status = :idle
      fire(event: :exited, code: exit_status&.exitstatus || 0)
    end

    def build_argv(url)
      ['ffplay', '-nodisp', '-autoexit', '-loglevel', 'warning',
       '-rtsp_transport', 'tcp', '-vn', '-sn', url]
    end

    private

    def fire(payload)
      @on_event&.call({ camera: @camera.id, type: :audio }.merge(payload))
    end
  end
end
