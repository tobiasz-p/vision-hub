# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe VisionHub::Configuration do
  describe ".parse" do
    subject(:config) { described_class.parse(json) }

    context "with a valid document" do
      let(:json) do
        <<~JSON
          {
            "cameras": [
              { "id": "front", "name": "Front door", "host": "10.0.0.5" },
              { "id": "garage", "host": "10.0.0.6", "enabled": false }
            ]
          }
        JSON
      end

      it "parses cameras and keeps only enabled cameras active" do
        expect(config).to be_ok
        expect(config.cameras.map(&:id)).to eq(%w[front garage])
        expect(config.active_cameras.map(&:id)).to eq(%w[front])
      end
    end

    context "with malformed JSON" do
      let(:json) { "{nope" }

      it "reports malformed JSON verbatim" do
        expect(config).not_to be_ok
        expect(config.error).to include("invalid JSON")
      end
    end

    context "when top-level is an array" do
      let(:json) { "[]" }

      it "rejects top-level array" do
        expect(config.error).to include('top level must be an object with a "cameras" array')
      end
    end

    context "when cameras key is missing" do
      let(:json) { "{}" }

      it "rejects missing cameras key" do
        expect(config.error).to include('"cameras" array')
      end
    end

    context "with duplicate camera ids" do
      let(:json) do
        <<~JSON
          { "cameras": [{ "id": "front", "host": "a" }, { "id": "front", "host": "b" }] }
        JSON
      end

      it "rejects duplicate ids with both indexes named" do
        expect(config.error).to include('duplicate id "front" (also at index 0)')
      end
    end

    context "when camera count exceeds MAX_CAMERAS" do
      let(:cams) { (1..(described_class::MAX_CAMERAS + 1)).map { |i| { "id" => "cam#{i}", "host" => "10.0.0.#{i}" } } }
      let(:json) { { "cameras" => cams }.to_json }

      it "rejects excessive camera counts" do
        expect(config.error).to include("exceeds maximum limit of #{described_class::MAX_CAMERAS}")
      end
    end
  end

  describe ".load" do
    subject(:config) { described_class.load(path) }

    context "when file exists" do
      let(:tmp_dir) { Dir.mktmpdir }
      let(:path) { File.join(tmp_dir, "cameras.json") }

      before do
        File.write(path, '{ "cameras": [{ "id": "front", "host": "10.0.0.5" }] }')
      end

      after do
        FileUtils.remove_entry(tmp_dir) if File.directory?(tmp_dir)
      end

      it "reads the configuration from disk" do
        expect(config.camera_by_id("front").host).to eq("10.0.0.5")
      end
    end

    context "when file does not exist" do
      let(:path) { "/nonexistent/vision-hub/cameras.json" }

      it "survives missing file with an error attached" do
        expect(config).not_to be_ok
        expect(config.error).to include("No such file")
        expect(config.active_cameras).to be_empty
      end
    end

    context "when file exceeds MAX_BYTES" do
      let(:tmp_dir) { Dir.mktmpdir }
      let(:path) { File.join(tmp_dir, "huge.json") }

      before do
        File.binwrite(path, "x" * (described_class::MAX_BYTES + 10))
      end

      after do
        FileUtils.remove_entry(tmp_dir) if File.directory?(tmp_dir)
      end

      it "caps absurdly large files with an error" do
        expect(config.error).to include("exceeds")
      end
    end
  end

  describe "#camera_by_id" do
    subject(:found_camera) { config.camera_by_id(camera_id) }

    let(:config) do
      described_class.parse(<<~JSON)
        {
          "cameras": [
            { "id": "front", "host": "10.0.0.5" },
            { "id": "off", "host": "10.0.0.6", "enabled": false }
          ]
        }
      JSON
    end

    context "when looking up an enabled camera" do
      let(:camera_id) { "front" }

      it "returns the camera instance" do
        expect(found_camera).to be_a(VisionHub::Camera)
      end
    end

    context "when looking up a disabled camera" do
      let(:camera_id) { "off" }

      it "returns nil" do
        expect(found_camera).to be_nil
      end
    end
  end

  describe "#ok?" do
    subject(:ok?) { config.ok? }

    context "when configuration is valid" do
      let(:config) { described_class.new([]) }

      it "returns true" do
        expect(ok?).to be true
      end
    end

    context "when configuration has an error" do
      let(:config) { described_class.new([], error: "something failed") }

      it "returns false" do
        expect(ok?).to be false
      end
    end
  end

  describe "#active_cameras" do
    subject(:active_cameras) { config.active_cameras }

    let(:config) do
      described_class.parse(<<~JSON)
        {
          "cameras": [
            { "id": "front", "host": "10.0.0.5" },
            { "id": "off", "host": "10.0.0.6", "enabled": false }
          ]
        }
      JSON
    end

    it "returns only cameras that are enabled" do
      expect(active_cameras.map(&:id)).to eq(%w[front])
    end
  end
end
