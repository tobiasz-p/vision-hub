# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Ipc do
  describe ".encode" do
    it "emits one terminated JSON line" do
      expect(described_class.encode({ type: "ping" })).to eq("{\"type\":\"ping\"}\n")
    end
  end

  describe described_class::Reader do
    subject(:reader) { described_class.new }

    def feed(chunk)
      reader.feed(chunk)
    end

    it "parses a single message" do
      results = feed("{\"type\":\"hello\"}\n")

      expect(results.size).to eq(1)
      expect(results.first.kind).to eq(:message)
      expect(results.first.message).to eq("type" => "hello")
    end

    it "parses several messages from one chunk" do
      results = feed("{\"a\":1}\n{\"b\":2}\n")

      expect(results.map(&:kind)).to eq(%i[message message])
      expect(results.map { |r| r.message["a"] || r.message["b"] }).to contain_exactly(1, 2)
    end

    it "reassembles messages split across chunks" do
      expect(feed('{"ty')).to be_empty
      results = feed("pe\":\"ping\"}\n")

      expect(results.map(&:message)).to include({ "type" => "ping" })
    end

    it "skips empty lines silently" do
      results = feed("\n\n{\"ok\":true}\n\n")

      expect(results.map(&:kind)).to eq([:message])
    end

    it "reports non-object JSON as invalid without stopping the stream" do
      results = feed("[1,2]\n\"bare\"\n{\"good\":true}\n")

      expect(results.map(&:kind)).to eq(%i[invalid invalid message])
      expect(results.last.message).to eq("good" => true)
    end

    it "drops an oversized line and keeps reading afterwards" do
      huge = "{\"junk\":\"#{"x" * (VisionHub::Ipc::MAX_LINE_BYTES + 1)}\"}"
      results = reader.feed("#{huge}\n{\"ok\":1}\n")

      expect(results.map(&:kind)).to eq(%i[oversize message])
    end

    it "caps a runaway line that has no newline yet" do
      first = reader.feed("x" * (VisionHub::Ipc::MAX_LINE_BYTES + 10))
      expect(first.map(&:kind)).to eq([:oversize])

      # The tail of the runaway line is discarded; the next real message lands.
      second = reader.feed("still junk\n{\"after\":true}\n")
      expect(second.map(&:kind)).to eq([:message])
      expect(second.first.message).to eq("after" => true)
    end

    it "keeps a trailing fragment waiting for its newline" do
      results = reader.feed('{"partial":')

      expect(results).to be_empty
    end
  end
end
