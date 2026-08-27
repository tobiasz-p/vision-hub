# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::SecretStore do
  subject(:store) { described_class.new(application_id: "tobiasz-p.vision-hub", runner:) }

  let(:calls) { [] }
  let(:lookup_result) { [true, "", ""] }
  let(:runner) do
    lambda do |argv|
      calls << argv
      lookup_result
    end
  end

  describe "#lookup" do
    subject(:secret) { store.lookup(camera_id) }

    let(:camera_id) { "front" }

    context "when credential exists in the keyring" do
      let(:lookup_result) { [true, "s3cret\n", ""] }

      it "returns the secret and invokes secret-tool with attribute-style arguments" do
        expect(secret).to eq("s3cret")
        expect(calls.last).to eq(["secret-tool", "lookup", "application", "tobiasz-p.vision-hub", "camera", "front"])
      end
    end

    context "when the keyring has no entry" do
      let(:lookup_result) { [false, "", "No result"] }

      it "returns nil" do
        expect(secret).to be_nil
      end
    end

    context "when keyring returns empty stdout on success" do
      let(:lookup_result) { [true, "\n", ""] }

      it "returns nil" do
        expect(secret).to be_nil
      end
    end

    context "when queried repeatedly" do
      it "caches hits and re-queries misses" do
        lookup_result.replace([true, "pw", ""])
        expect(store.lookup("front")).to eq("pw")

        lookup_result.replace([false, "", ""])
        expect(store.lookup("front")).to eq("pw")
        expect(store.lookup("garage")).to be_nil
        expect(calls.size).to eq(3)

        lookup_result.replace([true, "late", ""])
        expect(store.lookup("garage")).to eq("late")
        expect(calls.size).to eq(4)
      end
    end

    context "when specific camera is missing but default camera secret exists" do
      let(:lookup_map) { { "default" => [true, "shared_pass", ""] } }
      let(:runner) do
        lambda do |argv|
          cam = argv[argv.index("camera") + 1]
          lookup_map[cam] || [false, "", "No result"]
        end
      end
      let(:camera_id) { "cam2" }

      it "falls back to default camera secret" do
        expect(secret).to eq("shared_pass")
      end
    end
  end

  describe "#configured?" do
    subject(:configured?) { store.configured?(camera_id) }

    let(:camera_id) { "front" }

    context "when credential exists" do
      let(:lookup_result) { [true, "secret\n", ""] }

      it "returns true" do
        expect(configured?).to be true
      end
    end

    context "when credential is missing" do
      let(:lookup_result) { [false, "", "No result"] }

      it "returns false" do
        expect(configured?).to be false
      end
    end
  end

  describe "#clear_cache!" do
    subject(:clear_cache) { store.clear_cache! }

    before do
      lookup_result.replace([true, "old", ""])
      store.lookup("front")
      lookup_result.replace([true, "new", ""])
    end

    context "when cache has existing entries" do
      it "re-queries the keyring on subsequent lookups" do
        clear_cache

        expect(store.lookup("front")).to eq("new")
      end
    end
  end

  describe ".store_command" do
    subject(:command) { described_class.store_command("app-id", "cam1") }

    it "formats the secret-tool command line" do
      expect(command).to eq("secret-tool store --label='VisionHub camera cam1' application app-id camera cam1")
    end
  end

  describe "#store_command_for" do
    subject(:command) { store.store_command_for(camera_id) }

    let(:camera_id) { "front" }

    context "when generating the store hint" do
      it "builds a command containing attributes but no secret material" do
        expect(command).to include("secret-tool store --label='VisionHub camera front'")
        expect(command).to include("application tobiasz-p.vision-hub camera front")
        expect(command).not_to include("s3cret")
      end
    end
  end
end
