# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::HealthProbe do
  subject(:probe) do
    described_class.new(
      timeout:,
      socket_class:,
      select_fn:
    )
  end

  let(:timeout) { 0.5 }
  let(:socket_class) { Socket }
  let(:select_fn) { IO.method(:select) }

  let(:select_writable_on_second_call) do
    calls = { n: 0 }
    lambda do |*_args|
      calls[:n] += 1
      calls[:n] == 1 ? [[], [], nil] : [[], [:writable], nil]
    end
  end

  describe "#probe" do
    subject(:result) { probe.probe(host, port) }

    let(:host) { "127.0.0.1" }
    let(:port) { 554 }

    context "when target port is open and listening" do
      let(:server) { TCPServer.new("127.0.0.1", 0) }
      let(:port) { server.addr[1] }

      after { server.close }

      it "reports online" do
        expect(result).to eq(:online)
      end
    end

    context "when connection is refused" do
      let(:port) do
        server = TCPServer.new("127.0.0.1", 0)
        p = server.addr[1]
        server.close
        p
      end

      it "reports offline" do
        expect(result).to eq(:offline)
      end
    end

    context "when DNS resolution fails" do
      let(:timeout) { 0.2 }
      let(:host) { "invalid.invalid." }

      it "maps DNS failure to offline instead of raising" do
        expect(result).to eq(:offline)
      end
    end

    context "when socket never becomes writable" do
      let(:timeout) { 0.05 }
      let(:socket_class) { Fakes::NonWritableSocket }
      let(:select_fn) { ->(*) { [] } }
      let(:host) { "10.9.9.9" }

      it "times out and reports offline" do
        expect(result).to eq(:offline)
      end
    end

    context "when socket becomes writable on retry" do
      let(:socket_class) { Fakes::RetryingSocket }
      let(:select_fn) { select_writable_on_second_call }
      let(:host) { "10.9.9.9" }

      it "completes once select reports writability" do
        expect(result).to eq(:online)
      end
    end

    context "when checking socket teardown" do
      let(:timeout) { 0.05 }
      let(:closed_sockets) { [] }
      let(:socket_class) do
        closed = closed_sockets
        Class.new(Fakes::NonWritableSocket) do
          define_method(:close) { closed << self }
        end
      end
      let(:select_fn) { ->(*) { [] } }
      let(:host) { "10.9.9.9" }

      it "closes the socket on every path" do
        result
        expect(closed_sockets.size).to eq(1)
      end
    end
  end
end
