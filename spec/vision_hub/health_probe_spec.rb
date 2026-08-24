# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::HealthProbe do
  # Stands in for Socket when exercising the timeout path without a network.
  let(:fake_socket_class) do
    Class.new do
      def initialize(*); end

      def connect_nonblock(_address)
        raise WAIT_WRITABLE
      end

      def close; end
    end
  end

  # Socket that refuses the first connect attempt and succeeds on retry —
  # the standard EINPROGRESS handshake, faked.
  let(:retrying_socket_class) do
    Class.new(fake_socket_class) do
      def connect_nonblock(_address)
        @tries ||= 0
        @tries += 1
        raise WAIT_WRITABLE if @tries == 1

        :ok
      end
    end
  end

  let(:select_writable_on_second_call) do
    calls = { n: 0 }
    lambda do |*_args|
      calls[:n] += 1
      calls[:n] == 1 ? [[], [], nil] : [[], [:writable], nil]
    end
  end

  it "reports online for a listening local port" do
    server = TCPServer.new("127.0.0.1", 0)
    begin
      probe = described_class.new(timeout: 0.5)

      expect(probe.probe("127.0.0.1", server.addr[1])).to eq(:online)
    ensure
      server.close
    end
  end

  it "reports offline when the connection is refused" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    expect(described_class.new(timeout: 0.5).probe("127.0.0.1", port)).to eq(:offline)
  end

  it "maps DNS failure to offline instead of raising" do
    expect(described_class.new(timeout: 0.2).probe("invalid.invalid.", 554)).to eq(:offline)
  end

  it "times out a socket that never becomes writable" do
    probe = described_class.new(timeout: 0.05, socket_class: fake_socket_class, select_fn: ->(*) { [] })

    expect(probe.probe("10.9.9.9", 554)).to eq(:offline)
  end

  it "completes once select reports writability" do
    probe = described_class.new(
      timeout: 0.5, socket_class: retrying_socket_class, select_fn: select_writable_on_second_call
    )

    expect(probe.probe("10.9.9.9", 554)).to eq(:online)
  end

  it "closes the socket on every path, including refusal" do
    closed = []
    socket_class = Class.new(fake_socket_class) do
      define_method(:close) { closed << self }
    end
    probe = described_class.new(timeout: 0.05, socket_class:, select_fn: ->(*) { [] })

    probe.probe("10.9.9.9", 554)

    expect(closed.size).to eq(1)
  end
end
