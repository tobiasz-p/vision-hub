# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Camera do
  def build(overrides = {})
    described_class.from_hash({ "id" => "front", "host" => "10.0.0.5" }.merge(overrides), 0)
  end

  describe ".from_hash defaults and parsing" do
    it "applies the documented defaults" do
      camera = build

      expect(camera.port).to eq(554)
      expect(camera.name).to eq("front")
      expect(camera.main_path).to eq("/stream1")
      expect(camera.sub_path).to eq("/stream2")
      expect(camera.username).to be_nil
      expect(camera).to be_enabled
    end

    it "keeps explicit values" do
      camera = build(
        "name" => "Front door", "port" => 8554, "username" => "admin",
        "mainPath" => "/h264", "subPath" => "/sub", "enabled" => false
      )

      expect(camera.name).to eq("Front door")
      expect(camera.port).to eq(8554)
      expect(camera.username).to eq("admin")
      expect(camera.main_path).to eq("/h264")
      expect(camera.sub_path).to eq("/sub")
      expect(camera).not_to be_enabled
    end

    it "ignores unknown keys for forward compatibility" do
      expect { build("futureField" => 1) }.not_to raise_error
    end
  end

  describe ".from_hash validation" do
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
      ["null subPath", { "id" => "f", "host" => "h", "subPath" => nil }, /subPath must be a string beginning/]
    ].each do |label, entry, expected|
      it "rejects #{label}" do
        expect { described_class.from_hash(entry, 0) }.to raise_error(VisionHub::ConfigError, expected)
      end
    end

    it "reports the offending index in errors" do
      expect { described_class.from_hash({ "host" => "x" }, 3) }
        .to raise_error(VisionHub::ConfigError, /cameras\[3\]\.id/)
    end
  end

  describe "URL building" do
    it "builds an anonymous URL without userinfo" do
      expect(build.substream_url).to eq("rtsp://10.0.0.5:554/stream2")
    end

    it "embeds percent-encoded credentials" do
      camera = build("username" => "admin", "host" => "cam.local")

      expect(camera.mainstream_url("p@a:ss/w rd%"))
        .to eq("rtsp://admin:p%40a%3Ass%2Fw%20rd%25@cam.local:554/stream1")
    end

    it "encodes UTF-8 credentials byte-wise" do
      camera = build("username" => "üser")

      expect(camera.url_for("/s", "päss")).to include("rtsp://%C3%BCser:p%C3%A4ss@10.0.0.5:554/s")
    end

    it "treats a missing password as empty rather than crashing" do
      camera = build("username" => "admin")

      expect(camera.substream_url(nil)).to eq("rtsp://admin:@10.0.0.5:554/stream2")
    end
  end

  describe "#wants_password?" do
    it "is false for anonymous cameras" do
      expect(build).not_to be_wants_password
    end

    it "is true once a username is configured" do
      expect(build("username" => "admin")).to be_wants_password
    end
  end
end
