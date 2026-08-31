# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe VisionHub::Configuration do
  describe ".parse" do
    it "parses a valid document and keeps only enabled cameras active" do
      config = described_class.parse(<<~JSON)
        {
          "cameras": [
            { "id": "front", "name": "Front door", "host": "10.0.0.5" },
            { "id": "garage", "host": "10.0.0.6", "enabled": false }
          ]
        }
      JSON

      expect(config).to be_ok
      expect(config.cameras.map(&:id)).to eq(%w[front garage])
      expect(config.active_cameras.map(&:id)).to eq(%w[front])
    end

    it "reports malformed JSON verbatim" do
      config = described_class.parse("{nope")

      expect(config).not_to be_ok
      expect(config.error).to include("invalid JSON")
    end

    it "rejects a top-level array" do
      config = described_class.parse("[]")

      expect(config.error).to include('top level must be an object with a "cameras" array')
    end

    it "rejects a missing cameras key" do
      config = described_class.parse("{}")

      expect(config.error).to include('"cameras" array')
    end

    it "rejects duplicate ids with both indexes named" do
      config = described_class.parse(<<~JSON)
        { "cameras": [{ "id": "front", "host": "a" }, { "id": "front", "host": "b" }] }
      JSON

      expect(config.error).to include('duplicate id "front" (also at index 0)')
    end

    it "rejects camera counts exceeding MAX_CAMERAS" do
      cams = (1..(described_class::MAX_CAMERAS + 1)).map { |i| { "id" => "cam#{i}", "host" => "10.0.0.#{i}" } }
      config = described_class.parse({ "cameras" => cams }.to_json)

      expect(config.error).to include("exceeds maximum limit of #{described_class::MAX_CAMERAS}")
    end
  end

  describe ".load" do
    it "reads the file from disk" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "cameras.json")
        File.write(path, '{ "cameras": [{ "id": "front", "host": "10.0.0.5" }] }')

        config = described_class.load(path)

        expect(config.camera_by_id("front").host).to eq("10.0.0.5")
      end
    end

    it "survives a missing file with an error attached" do
      config = described_class.load("/nonexistent/vision-hub/cameras.json")

      expect(config).not_to be_ok
      expect(config.error).to include("No such file")
      expect(config.active_cameras).to be_empty
    end

    it "caps absurdly large files" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "huge.json")
        File.binwrite(path, "x" * (described_class::MAX_BYTES + 10))

        config = described_class.load(path)

        expect(config.error).to include("exceeds")
      end
    end

    it "rejects symlinks" do
      Dir.mktmpdir do |dir|
        real_file = File.join(dir, "real.json")
        link_file = File.join(dir, "link.json")
        File.write(real_file, '{ "cameras": [{ "id": "front", "host": "10.0.0.5" }] }')
        File.symlink(real_file, link_file)

        config = described_class.load(link_file)

        expect(config).not_to be_ok
        expect(config.error).to match(/Errno::ELOOP|Too many levels of symbolic links/i)
      end
    end

    it "rejects non-regular files such as directories" do
      Dir.mktmpdir do |dir|
        config = described_class.load(dir)

        expect(config).not_to be_ok
        expect(config.error).to include("not a regular file")
      end
    end
  end

  describe "#camera_by_id" do
    it "looks up among enabled cameras only" do
      config = described_class.parse(<<~JSON)
        {
          "cameras": [
            { "id": "front", "host": "10.0.0.5" },
            { "id": "off", "host": "10.0.0.6", "enabled": false }
          ]
        }
      JSON

      expect(config.camera_by_id("front")).to be_a(VisionHub::Camera)
      expect(config.camera_by_id("off")).to be_nil
    end
  end
end
