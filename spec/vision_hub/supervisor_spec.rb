# frozen_string_literal: true

require "spec_helper"

RSpec.describe VisionHub::Supervisor do
  subject(:supervisor) do
    described_class.new(
      cameras:, runtime_dir: "/run/vision-hub", secrets:,
      fps: 5, main_fps: 15, hwaccel: true, input_strategy: :argv,
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

  let(:pumps_by_id_role) { {} }
  let(:build_pump) do
    lambda do |kwargs|
      fake = Fakes::Pump.new(kwargs)
      pumps_by_id_role[[kwargs[:camera].id, kwargs[:role]]] = fake
      fake
    end
  end

  describe "#start" do
    subject(:start) { supervisor.start(now: 0) }

    context "with configured cameras" do
      it "starts sub-stream pumps for every camera and publishes initial state" do
        start

        expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
        expect(pumps_by_id_role[["garage", :sub]].running?).to be(true)
        expect(pumps_by_id_role[["front", :main]]).to be_nil

        events = supervisor.drain_outbox
        expect(events.first[:event]).to eq(:hello)
        expect(events.count { |e| e[:event] == :camera_state }).to eq(2)
      end
    end

    context "with unconfigured cameras" do
      let(:supervisor) do
        described_class.new(
          cameras: [cameras[0]], runtime_dir: "/run/vision-hub", secrets: Fakes::Secrets.new,
          fps: 5, main_fps: 15, hwaccel: true, input_strategy: :argv,
          build_pump: ->(kw) { Fakes::Pump.new(kw).tap { |p| p.start_mode = :unconfigured } },
          probe_runner:
        )
      end

      it "reports unconfigured error through the state stream" do
        start
        supervisor.handle({ "cmd" => "window", "open" => true }, now: 0)

        expect(supervisor.drain_outbox).to include(
          hash_including(event: :camera_state, id: "front", error: "credentials not found in keyring")
        )
      end
    end
  end

  describe "#tick" do
    before do
      supervisor.start(now: 0)
      supervisor.drain_outbox
    end

    context "when advancing time" do
      it "advances every pump with the injected time" do
        supervisor.tick(now: 1)

        expect(pumps_by_id_role[["front", :sub]].events).to include([:tick, 1])
        expect(pumps_by_id_role[["garage", :sub]].events).to include([:tick, 1])
      end
    end

    context "when probing cameras round-robin" do
      it "probes one camera per tick and publishes transitions once" do
        probe_results["front"] = :offline
        supervisor.tick(now: 11)

        front_event = supervisor.drain_outbox.rfind { |e| e[:event] == :camera_state && e[:id] == "front" }
        expect(front_event).to include(online: false)

        supervisor.tick(now: 21)
        garage_event = supervisor.drain_outbox.rfind { |e| e[:event] == :camera_state && e[:id] == "garage" }
        expect(garage_event).to include(online: true)

        supervisor.tick(now: 31)
        expect(supervisor.drain_outbox).to be_empty
      end
    end

    context "when a pump crashes" do
      it "propagates pump crashes into streaming=false plus error detail" do
        pumps_by_id_role[["front", :sub]].fail_later("ffmpeg exited with code 255: Connection refused")
        supervisor.tick(now: 2)

        front_event = supervisor.drain_outbox.rfind { |e| e[:event] == :camera_state && e[:id] == "front" }
        expect(front_event).to include(
          online: true, streaming: false,
          error: "ffmpeg exited with code 255: Connection refused"
        )
      end
    end

    context "when state has not changed" do
      it "emits no events" do
        supervisor.tick(now: 3)
        supervisor.tick(now: 13)
        supervisor.drain_outbox

        supervisor.tick(now: 23)
        supervisor.tick(now: 33)

        expect(supervisor.drain_outbox).to be_empty
      end
    end
  end

  describe "#handle" do
    subject(:handle) { supervisor.handle(command, now:) }

    let(:now) { 1 }
    let(:command) { { "cmd" => "window", "open" => true } }

    before do
      supervisor.start(now: 0)
      supervisor.drain_outbox
    end

    context "with window command" do
      it "starts grid streams when window opens and stops them when window closes" do
        handle
        expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
        expect(pumps_by_id_role[["garage", :sub]].running?).to be(true)

        supervisor.handle({ "cmd" => "window", "open" => false }, now: 2)
        expect(pumps_by_id_role[["front", :sub]].running?).to be(false)
        expect(pumps_by_id_role[["garage", :sub]].running?).to be(false)
      end
    end

    context "with focus command" do
      let(:command) { { "cmd" => "focus", "camera" => "front" } }
      let(:now) { 10 }

      it "starts the main pump for the focused camera only" do
        handle

        expect(pumps_by_id_role[["front", :main]].running?).to be(true)
        expect(pumps_by_id_role[["garage", :main]]).to be_nil
        expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(15)
      end

      context "when switching focus to another camera" do
        it "stops the previous focus stream and starts the new one" do
          handle
          supervisor.handle({ "cmd" => "focus", "camera" => "garage" }, now: 11)

          expect(pumps_by_id_role[["front", :main]].running?).to be(false)
          expect(pumps_by_id_role[["garage", :main]].running?).to be(true)
        end
      end

      context "when specifying a custom fps" do
        let(:command) { { "cmd" => "focus", "camera" => "front", "fps" => 25 } }

        it "uses the specified fps for the main pump" do
          handle

          expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(25)
        end
      end

      context "when camera is unknown" do
        let(:command) { { "cmd" => "focus", "camera" => "nope" } }

        it "emits an error event" do
          handle

          expect(supervisor.drain_outbox.last).to include(
            event: :error, message: 'focus: unknown camera "nope"'
          )
        end
      end
    end

    context "with unfocus command" do
      let(:command) { { "cmd" => "unfocus" } }
      let(:now) { 12 }

      it "stops the main pump and resumes sub streams when window is open" do
        supervisor.handle({ "cmd" => "window", "open" => true }, now: 0)
        supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)
        handle

        expect(pumps_by_id_role[["front", :main]].running?).to be(false)
        expect(pumps_by_id_role[["front", :sub]].running?).to be(true)
      end
    end

    context "with set_fps command" do
      let(:command) { { "cmd" => "set_fps", "fps" => 30 } }
      let(:now) { 12 }

      it "updates running stream dynamically" do
        supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 10)
        expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(15)

        handle
        expect(pumps_by_id_role[["front", :main]].kwargs[:fps]).to eq(30)
      end
    end

    context "with ping command" do
      let(:command) { { "cmd" => "ping", "echo" => 42 } }

      it "responds with pong and echoes payload" do
        handle

        expect(supervisor.drain_outbox.last).to include(event: :pong, echo: 42)
      end
    end

    context "with refresh command" do
      let(:command) { { "cmd" => "refresh" } }
      let(:now) { 0.5 }

      it "probes every camera immediately" do
        probe_results["garage"] = :offline
        handle

        garage_event = supervisor.drain_outbox.rfind { |e| e[:event] == :camera_state && e[:id] == "garage" }
        expect(garage_event).to include(online: false)
      end
    end

    context "with next and prev commands" do
      it "cycles through cameras in order" do
        supervisor.handle({ "cmd" => "next" }, now: 1)
        expect(pumps_by_id_role[["front", :main]].running?).to be(true)

        supervisor.handle({ "cmd" => "next" }, now: 2)
        expect(pumps_by_id_role[["garage", :main]].running?).to be(true)

        supervisor.handle({ "cmd" => "prev" }, now: 3)
        expect(pumps_by_id_role[["front", :main]].running?).to be(true)
      end
    end

    context "with an unknown command" do
      let(:command) { { "cmd" => "explode" } }

      it "emits an error event" do
        handle

        expect(supervisor.drain_outbox.last).to include(event: :error, message: include("explode"))
      end
    end

    context "when publishing state updates" do
      it "emits summary and frame_url" do
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

  describe "#drain_outbox" do
    subject(:drained) { supervisor.drain_outbox }

    before { supervisor.start(now: 0) }

    it "returns queued events and clears the outbox" do
      expect(drained).not_to be_empty
      expect(supervisor.drain_outbox).to be_empty
    end
  end

  describe "#shutdown" do
    subject(:shutdown) { supervisor.shutdown(now: 100) }

    before do
      supervisor.start(now: 0)
      supervisor.drain_outbox
      supervisor.handle({ "cmd" => "focus", "camera" => "front" }, now: 5)
    end

    it "stops every pump including the focused main stream" do
      shutdown

      expect(pumps_by_id_role[["front", :sub]].running?).to be(false)
      expect(pumps_by_id_role[["front", :main]].running?).to be(false)
      expect(pumps_by_id_role[["garage", :sub]].running?).to be(false)
    end

    context "when called repeatedly" do
      it "tolerates subsequent calls without error" do
        shutdown

        expect { supervisor.shutdown(now: 101) }.not_to raise_error
      end
    end
  end
end
