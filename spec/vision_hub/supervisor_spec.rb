# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Supervisor do
  subject(:supervisor) do
    described_class.new(
      cameras:, runtime_dir: "/run/vision-hub", secrets:,
      fps: 5, main_fps: 15, hwaccel: true,
      probe_interval:, logger: nil,
      build_pump:, probe_runner:
    )
  end

  let(:cameras) do
    [
      VisionHub::Camera.from_hash({ "id" => "front", "host" => "10.0.0.5", "username" => "admin" }, 0),
      VisionHub::Camera.from_hash({ "id" => "garage", "host" => "10.0.0.6", "username" => "admin" }, 1)
    ]
  end
  let(:secrets) { Fakes::Secrets.new("front" => "pw", "garage" => "pw") }
  let(:probe_interval) { 10.0 }
  let(:probe_results) { Hash.new(:online) }
  let(:probe_runner) { ->(camera) { probe_results[camera.id] } }

  # Fake pump registry keyed by [camera_id, role].
  let(:pumps_by_id_role) { {} }
  let(:build_pump) do
    lambda do |kwargs|
      fake = Fakes::Pump.new(kwargs)
      pumps_by_id_role[[kwargs[:camera].id, kwargs[:role]]] = fake
      fake
    end
  end

  # Drops everything queued so far; assertions only see fresh traffic.
  def flush!
    supervisor.drain_outbox
  end

  def event_kinds
    supervisor.drain_outbox.map { |e| e[:event] }
  end

  def state_event(camera_id)
    supervisor.drain_outbox.rfind { |e| e[:event] == :camera_state && e[:id] == camera_id }
  end

  describe "#start" do
    it "starts sub-stream pumps for every camera and says hello first" do
      supervisor.start(now: 0)

      expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
      expect(pumps_by_id_role[["garage", :sub]].running?).to be(true)
      expect(pumps_by_id_role[["front", :main]]).to be_nil
      kinds = event_kinds
      expect(kinds.first).to eq(:hello)
      expect(kinds.count(:camera_state)).to eq(2)
    end

    it "starts grid streams when window opens and stops them when window closes" do
      supervisor.start(now: 0)
      flush!

      supervisor.handle({ "cmd" => "window", "open" => true }, now: 1)
      expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
      expect(pumps_by_id_role[["garage", :sub]].running?).to be(true)

      supervisor.handle({ "cmd" => "window", "open" => false }, now: 2)
      expect(pumps_by_id_role[["front", :sub]].running?).to be(false)
      expect(pumps_by_id_role[["garage", :sub]].running?).to be(false)
    end

    it "reports unconfigured cameras through the state stream" do
      bare = described_class.new(
        cameras: [cameras[0]], runtime_dir: "/run/vision-hub", secrets: Fakes::Secrets.new,
        fps: 5, main_fps: 15, hwaccel: true,
        build_pump: ->(kw) { Fakes::Pump.new(kw).tap { |p| p.start_mode = :unconfigured } },
        probe_runner:
      )
      bare.start(now: 0)
      bare.handle({ "cmd" => "window", "open" => true }, now: 0)

      expect(bare.drain_outbox).to include(
        hash_including(event: :camera_state, id: "front", error: "credentials not found in keyring")
      )
    end
  end

  describe "#tick" do
    before do
      supervisor.start(now: 0)
      flush!
    end

    it "advances every pump with the injected time" do
      supervisor.tick(now: 1)

      expect(pumps_by_id_role[["front", :sub]].events).to include([:tick, 1])
      expect(pumps_by_id_role[["garage", :sub]].events).to include([:tick, 1])
    end

    it "probes one camera per tick round-robin and publishes transitions once" do
      probe_results["front"] = :offline
      supervisor.tick(now: 11) # first round-robin slot

      expect(state_event("front")).to include(online: false)

      supervisor.tick(now: 21) # garage's turn: its own first verdict
      expect(state_event("garage")).to include(online: true)

      supervisor.tick(now: 31) # front revisited, unchanged → silence
      expect(event_kinds).to eq([])
    end

    it "propagates pump crashes into streaming=false plus the error text" do
      pumps_by_id_role[["front", :sub]].fail_later("ffmpeg exited with code 255: Connection refused")
      supervisor.tick(now: 2)

      expect(state_event("front")).to include(
        online: true, streaming: false,
        error: "ffmpeg exited with code 255: Connection refused"
      )
    end

    it "stays quiet when nothing changes" do
      supervisor.tick(now: 3) # front probed: nil → true
      supervisor.tick(now: 13) # garage probed: nil → true
      flush!

      supervisor.tick(now: 23)
      supervisor.tick(now: 33)

      expect(supervisor.drain_outbox).to be_empty
    end
  end

  describe "focus handling" do
    before do
      supervisor.start(now: 0)
      flush!
    end

    it "starts the main pump for the focused camera only" do
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)

      expect(pumps_by_id_role[["front", :main]].running?).to be(true)
      expect(pumps_by_id_role[["garage", :main]]).to be_nil
    end

    it "stops the previous focus when switching" do
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)
      supervisor.handle({ "cmd" => "focus", "camera" => "garage" }, now: 11)

      expect(pumps_by_id_role[["front", :main]].running?).to be(false)
      expect(pumps_by_id_role[["garage", :main]].running?).to be(true)
    end

    it "unfocus stops the main pump and resumes sub streams when window is open" do
      supervisor.handle({ "cmd" => "window", "open" => true }, now: 0)
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)
      supervisor.handle({ "cmd" => "unfocus" }, now: 12)

      expect(pumps_by_id_role[["front", :main]].running?).to be(false)
      expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
    end

    it "rejects unknown cameras with an error event" do
      supervisor.handle({ "cmd" => "focus", "camera" => "nope" }, now: 10)

      expect(supervisor.drain_outbox.last).to include(
        event: :error, message: 'focus: unknown camera "nope"'
      )
    end

    it "uses the higher fps for main-role pumps" do
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)

      expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(15)
    end

    it "accepts custom fps in focus command" do
      supervisor.handle({ "cmd" => "focus", "camera" => "front", "fps" => 25 }, now: 10)

      expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(25)
    end

    it "updates running stream dynamically on set_fps" do
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)
      expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(15)

      supervisor.handle({ "cmd" => "set_fps", "fps" => 30 }, now: 12)
      expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(30)
    end
  end

  describe "#shutdown" do
    before do
      supervisor.start(now: 0)
      flush!
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 5)
    end

    it "TERMs every pump including the focused main stream" do
      supervisor.shutdown(now: 100)

      expect(pumps_by_id_role[["front", :sub]].running?).to be(false)
      expect(pumps_by_id_role[["front", :main]].running?).to be(false)
      expect(pumps_by_id_role[["garage", :sub]].running?).to be(false)
    end

    it "tolerates being called twice" do
      supervisor.shutdown(now: 100)

      expect { supervisor.shutdown(now: 101) }.not_to raise_error
    end
  end

  describe "IPC commands" do
    before do
      supervisor.start(now: 0)
      flush!
    end

    it "answers ping with pong and echoes the payload" do
      supervisor.handle({ "cmd" => "ping", "echo" => 42 }, now: 1)

      expect(supervisor.drain_outbox.last).to include(event: :pong, echo: 42)
    end

    it "refresh probes every camera immediately" do
      probe_results["garage"] = :offline
      supervisor.handle({ "cmd" => "refresh" }, now: 0.5)

      expect(state_event("garage")).to include(online: false)
    end

    it "flags unknown commands" do
      supervisor.handle({ "cmd" => "explode" }, now: 1)

      expect(supervisor.drain_outbox.last).to include(event: :error, message: include("explode"))
    end

    it "cycles to next and previous cameras in order" do
      supervisor.handle({ "cmd" => "next" }, now: 1)
      expect(pumps_by_id_role[["front", :main]].running?).to be(true)

      supervisor.handle({ "cmd" => "next" }, now: 2)
      expect(pumps_by_id_role[["garage", :main]].running?).to be(true)

      supervisor.handle({ "cmd" => "prev" }, now: 3)
      expect(pumps_by_id_role[["front", :main]].running?).to be(true)
    end

    it "emits summary and frame_url on state publication" do
      probe_results["front"] = :online
      probe_results["garage"] = :online
      supervisor.tick(now: 11)
      supervisor.tick(now: 21)

      events = supervisor.drain_outbox
      summary = events.rfind { |e| e[:event] == :summary }
      expect(summary).to include(
        total: 2, online: 2, offline: 0,
        all_healthy: true, any_offline: false
      )
      expect(summary[:tooltip]).to include("front", "garage", "Left-click: open grid")

      camera_event = events.find { |e| e[:event] == :camera_state }
      expect(camera_event).to include(frame_url: include("file:///run/vision-hub/"))
    end
  end
end
