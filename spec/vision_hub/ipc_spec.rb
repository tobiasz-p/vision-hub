# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Ipc do
  describe ".encode" do
    subject(:encoded) { described_class.encode(message) }

    let(:message) { { type: "ping" } }

    context "with a message hash" do
      it "emits one newline-terminated JSON line" do
        expect(encoded).to eq("{\"type\":\"ping\"}\n")
      end
    end
  end

  describe VisionHub::Ipc::Reader do
    subject(:reader) { described_class.new }

    describe "#feed" do
      subject(:results) { reader.feed(chunk) }

      context "with a single message" do
        let(:chunk) { "{\"type\":\"hello\"}\n" }

        it "parses a single message" do
          expect(results.size).to eq(1)
          expect(results.first.kind).to eq(:message)
          expect(results.first.message).to eq("type" => "hello")
        end
      end

      context "with several messages in one chunk" do
        let(:chunk) { "{\"a\":1}\n{\"b\":2}\n" }

        it "parses all messages from the chunk" do
          expect(results.map(&:kind)).to eq(%i[message message])
          expect(results.map { |r| r.message["a"] || r.message["b"] }).to contain_exactly(1, 2)
        end
      end

      context "with messages split across chunks" do
        it "reassembles messages split across chunks" do
          expect(reader.feed('{"ty')).to be_empty
          subsequent = reader.feed("pe\":\"ping\"}\n")

          expect(subsequent.map(&:message)).to include({ "type" => "ping" })
        end
      end

      context "with empty lines" do
        let(:chunk) { "\n\n{\"ok\":true}\n\n" }

        it "skips empty lines silently" do
          expect(results.map(&:kind)).to eq([:message])
        end
      end

      context "with non-object JSON" do
        let(:chunk) { "[1,2]\n\"bare\"\n{\"good\":true}\n" }

        it "reports non-object JSON as invalid without stopping the stream" do
          expect(results.map(&:kind)).to eq(%i[invalid invalid message])
          expect(results.last.message).to eq("good" => true)
        end
      end

      context "with an oversized line" do
        let(:huge) { "{\"junk\":\"#{"x" * (VisionHub::Ipc::MAX_LINE_BYTES + 1)}\"}" }
        let(:chunk) { "#{huge}\n{\"ok\":1}\n" }

        it "drops the oversized line and keeps reading afterwards" do
          expect(results.map(&:kind)).to eq(%i[oversize message])
        end
      end

      context "with a runaway line without a newline" do
        let(:runaway_chunk) { "x" * (VisionHub::Ipc::MAX_LINE_BYTES + 10) }
        let(:subsequent_chunk) { "still junk\n{\"after\":true}\n" }

        it "caps the runaway line and parses the subsequent valid message" do
          first = reader.feed(runaway_chunk)
          expect(first.map(&:kind)).to eq([:oversize])

          second = reader.feed(subsequent_chunk)
          expect(second.map(&:kind)).to eq([:message])
          expect(second.first.message).to eq("after" => true)
        end
      end

      context "with a trailing fragment" do
        let(:chunk) { '{"partial":' }

        it "keeps the fragment buffered waiting for a newline" do
          expect(results).to be_empty
        end
      end
    end
  end
end
