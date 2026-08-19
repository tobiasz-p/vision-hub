# frozen_string_literal: true

require 'socket'

module VisionHub
  # Reachability check for one camera: a non-blocking TCP connect to the RTSP
  # port. Purely transport-level — an online camera may still fail auth or
  # stream negotiation, which the frame pump reports separately.
  class HealthProbe
    DEFAULT_TIMEOUT = 2.0

    def initialize(timeout: DEFAULT_TIMEOUT, socket_class: Socket, select_fn: IO.method(:select))
      @timeout = timeout
      @socket_class = socket_class
      @select_fn = select_fn
    end

    # Returns :online or :offline. Never raises; every failure mode maps to
    # :offline so the event loop cannot be killed by a hostile address.
    def probe(host, port)
      address = Addrinfo.tcp(host, port)
      socket = @socket_class.new(address.afamily, :STREAM, 0)
      connect(socket, address)
      :online
    rescue StandardError
      :offline
    ensure
      begin
        socket&.close
      rescue StandardError
        nil
      end
    end

    private

    def connect(socket, address)
      socket.connect_nonblock(address)
    rescue IO::WaitWritable
      await_connect(socket, address) || raise(Errno::ETIMEDOUT)
    end

    # Completes a non-blocking connect once the socket turns writable. True on
    # success; nil only when the deadline expires first.
    def await_connect(socket, address)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0

        ready = @select_fn.call([], [socket], nil, remaining)
        next unless ready && !ready[1].empty?

        begin
          socket.connect_nonblock(address)
          return true
        rescue Errno::EISCONN
          return true
        rescue IO::WaitWritable
          next
        end
      end
    end
  end
end
