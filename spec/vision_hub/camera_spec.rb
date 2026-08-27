# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Camera do
  let(:camera) { described_class.from_hash(attributes, 0) }
  let(:attributes) { { "id" => "front", "host" => "10.0.0.5" } }

  describe ".from_hash" do
    subject(:camera) { described_class.from_hash(attributes, index) }

    let(:index) { 0 }

    context "with default attributes" do
      it "applies documented defaults" do
        expect(camera.port).to eq(554)
        expect(camera.name).to eq("front")
        expect(camera.main_path).to eq("/stream1")
        expect(camera.sub_path).to eq("/stream2")
        expect(camera.username).to be_nil
        expect(camera).to be_enabled
      end
    end

    context "with explicit attributes" do
      let(:attributes) do
        {
          "id" => "front",
          "name" => "Front door",
          "host" => "10.0.0.5",
          "port" => 8554,
          "username" => "admin",
          "mainPath" => "/h264",
          "subPath" => "/sub",
          "enabled" => false
        }
      end

      it "preserves configured values" do
        expect(camera.name).to eq("Front door")
        expect(camera.port).to eq(8554)
        expect(camera.username).to eq("admin")
        expect(camera.main_path).to eq("/h264")
        expect(camera.sub_path).to eq("/sub")
        expect(camera).not_to be_enabled
      end
    end

    context "with unknown keys" do
      let(:attributes) { { "id" => "front", "host" => "10.0.0.5", "futureField" => 1 } }

      it "ignores unknown keys for forward compatibility" do
        expect { camera }.not_to raise_error
      end
    end

    context "with invalid attributes" do
      [
        ["missing id", { "host" => "h" }, /cameras\[0\]\.id is required/],
        ["empty id", { "id" => "", "host" => "h" }, /id is required/],
        ["path-like id", { "id" => "../escape", "host" => "h" }, /may only contain/],
        ["non-string name", { "id" => "f", "host" => "h", "name" => 7 }, /name must be a string/],
        ["missing host", { "id" => "f" }, /host is required/],
        ["string port", { "id" => "f", "host" => "h", "port" => "554" }, /port must be an integer/],
        ["zero port", { "id" => "f", "host" => "h", "port" => 0 }, /port must be an integer/],
        ["oversize port", { "id" => "f", "host" => "h", "port" => 65_536 }, /port must be an integer/],
        ["relative mainPath", { "id" => "f", "host" => "h", "mainPath" => "stream1" },
         /mainPath must be a string beginning/],
        ["null subPath", { "id" => "f", "host" => "h", "subPath" => nil }, /subPath must be a string beginning/],
        ["oversized id", { "id" => "a" * 65, "host" => "h" }, /id exceeds maximum length/],
        ["oversized name", { "id" => "f", "host" => "h", "name" => "a" * 129 }, /name exceeds maximum length/],
        ["oversized host", { "id" => "f", "host" => "a" * 256 }, /host exceeds maximum length/],
        ["oversized path", { "id" => "f", "host" => "h", "mainPath" => "/#{"a" * 513}" },
         /mainPath exceeds maximum length/]
      ].each do |label, entry, expected_error|
        context "when #{label}" do
          let(:attributes) { entry }

          it "raises ConfigError matching #{expected_error.inspect}" do
            expect { camera }.to raise_error(VisionHub::ConfigError, expected_error)
          end
        end
      end

      context "when reporting offending index in errors" do
        let(:index) { 3 }
        let(:attributes) { { "host" => "x" } }

        it "includes the index in the error message" do
          expect { camera }.to raise_error(VisionHub::ConfigError, /cameras\[3\]\.id/)
        end
      end
    end
  end

  describe "#substream_url" do
    subject(:substream_url) { camera.substream_url(password) }

    let(:password) { nil }

    context "without credentials" do
      it "builds an anonymous URL without userinfo" do
        expect(substream_url).to eq("rtsp://10.0.0.5:554/stream2")
      end
    end

    context "when password is nil for authenticated camera" do
      let(:attributes) { { "id" => "front", "host" => "10.0.0.5", "username" => "admin" } }

      it "treats a missing password as empty rather than crashing" do
        expect(substream_url).to eq("rtsp://admin:@10.0.0.5:554/stream2")
      end
    end
  end

  describe "#mainstream_url" do
    subject(:mainstream_url) { camera.mainstream_url(password) }

    let(:attributes) { { "id" => "front", "host" => "cam.local", "username" => "admin" } }
    let(:password) { "p@a:ss/w rd%" }

    context "with special characters in password" do
      it "embeds percent-encoded credentials" do
        expect(mainstream_url).to eq("rtsp://admin:p%40a%3Ass%2Fw%20rd%25@cam.local:554/stream1")
      end
    end
  end

  describe "#url_for" do
    subject(:url) { camera.url_for("/s", password) }

    let(:attributes) { { "id" => "front", "host" => "10.0.0.5", "username" => "üser" } }
    let(:password) { "päss" }

    context "with UTF-8 credentials" do
      it "encodes UTF-8 credentials byte-wise" do
        expect(url).to include("rtsp://%C3%BCser:p%C3%A4ss@10.0.0.5:554/s")
      end
    end
  end

  describe "#wants_password?" do
    subject(:wants_password?) { camera.wants_password? }

    context "when camera is anonymous" do
      it "returns false" do
        expect(camera).not_to be_wants_password
      end
    end

    context "when username is configured" do
      let(:attributes) { { "id" => "front", "host" => "10.0.0.5", "username" => "admin" } }

      it "returns true" do
        expect(camera).to be_wants_password
      end
    end
  end

  describe "#enabled?" do
    subject(:enabled?) { camera.enabled? }

    context "when enabled is true" do
      it "returns true" do
        expect(enabled?).to be true
      end
    end

    context "when enabled is false" do
      let(:attributes) { { "id" => "front", "host" => "10.0.0.5", "enabled" => false } }

      it "returns false" do
        expect(enabled?).to be false
      end
    end
  end

  describe ".percent_encode" do
    subject(:encoded) { described_class.percent_encode(value) }

    let(:value) { "p@a:ss/w rd%" }

    it "percent-encodes non-unreserved characters" do
      expect(encoded).to eq("p%40a%3Ass%2Fw%20rd%25")
    end
  end
end
