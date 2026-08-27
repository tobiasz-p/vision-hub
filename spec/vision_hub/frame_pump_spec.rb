# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"
require "fileutils"

RSpec.describe VisionHub::FramePump do
  subject(:pump) do
    described_class.new(
      camera:, role:, runtime_dir:, fps:, hwaccel:,
      audio:, input_strategy:, secrets:,
      spawner: harness.spawner, reaper: harness.reaper, killer: harness.killer
    ).on_event { |payload| events << payload }
  end

  let(:camera) do
    VisionHub::Camera.from_hash({ "id" => "front", "host" => "10.0.0.5", "username" => "admin" }, 0)
  end
  let(:role) { :sub }
  let(:fps) { 5 }
  let(:hwaccel) { true }
  let(:audio) { false }
  let(:input_strategy) { :argv }
  let(:secrets) { Fakes::Secrets.new("front" => "pw") }
  let(:events) { [] }
  let(:runtime_dir) { Dir.mktmpdir }
  let(:harness) { Fakes::ProcessHarness.new }

  after { FileUtils.remove_entry(runtime_dir) if File.directory?(runtime_dir) }

  describe "#build_argv" do
    subject(:argv) { pump.build_argv(url) }

    let(:url) { "rtsp://u:p@h/s" }

    context "with default options for sub role" do
      it "passes the URL directly and forces TCP with socket timeout" do
        expect(argv[argv.index("-i") + 1]).to eq("rtsp://u:p@h/s")
        expect(argv[argv.index("-timeout") + 1]).to eq(described_class::RTSP_TIMEOUT_US.to_s)
        expect(argv).not_to include("-f")
      end

      it "targets snapshot mode with scaled dimensions" do
        expect(argv).to end_with(File.join(runtime_dir, "front.jpg"))
        expect(argv).to include("-frames:v", "1", "-y", "-atomic_writing", "1")
        expect(argv[argv.index("-vf") + 1]).to eq("scale=w=640:h=480:force_original_aspect_ratio=decrease")
        expect(argv).to include("-hwaccel", "auto")
      end
    end

    context "with main role" do
      let(:role) { :main }
      let(:fps) { 20 }

      it "targets continuous streaming with configured fps and 1080p resolution" do
        expect(argv).to end_with(File.join(runtime_dir, "front.jpg"))
        expect(argv).to include("-update", "1", "-atomic_writing", "1", "-y")
        expect(argv[argv.index("-vf") + 1]).to eq("fps=20,scale=w=1920:h=1080:force_original_aspect_ratio=decrease")
        expect(argv).to include("-hwaccel", "auto")
      end
    end

    context "with audio enabled for main role" do
      let(:role) { :main }
      let(:fps) { 15 }
      let(:audio) { true }

      it "includes pulse audio output flags" do
        expect(argv).to include("-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", "-f", "pulse", "VisionHub")
      end
    end

    context "with hwaccel disabled" do
      let(:hwaccel) { false }

      it "omits hardware decode flags" do
        expect(argv).not_to include("-hwaccel")
      end
    end

    context "with concat_file strategy" do
      let(:input_strategy) { :concat_file }
      let(:url) { "rtsp://admin:s3cret@10.0.0.5/stream2" }
      let(:playlist) { File.join(runtime_dir, "front.sub.ffconcat") }

      it "writes a 0600 playlist and keeps credentials out of argv" do
        expect(argv).to include(playlist)
        expect(argv.join(" ")).not_to include("s3cret")
        expect(argv).to include("-protocol_whitelist")
        expect(playlist).to have_file_mode("600")
        expect(File.read(playlist)).to include("file 'rtsp://admin:s3cret@10.0.0.5/stream2'")
      end

      context "when URL contains single quotes" do
        let(:url) { "rtsp://a:b'c@d/s" }

        it "escapes single quotes in the playlist" do
          argv
          expect(File.read(playlist)).to include("b''c")
        end
      end
    end
  end

  describe "#start" do
    subject(:start) { pump.start(now:) }

    let(:now) { 100 }

    context "when starting an idle pump" do
      it "spawns ffmpeg once and reports running" do
        start

        expect(harness.spawned.size).to eq(1)
        expect(pump.status).to eq(:running)
        expect(events.map { |e| e[:event] }).to eq([:started])
      end
    end

    context "when already running or backing off" do
      it "ignores subsequent start calls" do
        start
        harness.exits[harness.last_pid] = 1
        pump.tick(now: 101)

        pump.start(now: 102)
        pump.start(now: 103)

        expect(harness.spawned.size).to eq(1)
      end
    end

    context "with main role" do
      let(:role) { :main }
      let(:fps) { 10 }

      it "uses the mainstream URL with credentials" do
        start

        url = harness.spawned[0][harness.spawned[0].index("-i") + 1]
        expect(url).to end_with("/stream1")
        expect(url).to include("admin:pw@")
      end
    end

    context "when camera is unconfigured without credentials" do
      let(:secrets) { Fakes::Secrets.new }

      it "does not spawn and reports unconfigured state" do
        start

        expect(harness.spawned).to be_empty
        expect(pump.status).to eq(:unconfigured)
        expect(events.last[:event]).to eq(:unconfigured)
      end
    end

    context "when camera is anonymous without authentication" do
      let(:now) { 0 }
      let(:camera) { VisionHub::Camera.from_hash({ "id" => "anon", "host" => "10.0.0.9" }, 0) }
      let(:secrets) do
        store = instance_double(VisionHub::SecretStore)
        allow(store).to receive(:lookup).and_raise(RuntimeError, "must never be called")
        store
      end

      it "spawns without consulting the keyring" do
        start

        expect(harness.spawned.size).to eq(1)
        expect(harness.spawned[0].join(" ")).to include("rtsp://10.0.0.9:554/stream2")
      end
    end
  end

  describe "#stop" do
    subject(:stop) { pump.stop(now:, immediate:) }

    let(:now) { 100 }
    let(:immediate) { false }

    context "when stopped gracefully" do
      it "sends TERM and transitions to stopped on reap confirmation" do
        pump.start(now: 100)
        stop

        expect(harness.signals.last).to eq([-harness.last_pid, "TERM"])
        expect(pump.status).to eq(:stopping)

        harness.exits[harness.last_pid] = 0
        pump.tick(now: 101)

        expect(pump.status).to eq(:stopped)
        expect(pump.running?).to be(false)
      end
    end

    context "when TERM is not answered past grace period" do
      it "escalates to KILL" do
        pump.start(now: 100)
        pid = harness.last_pid
        stop
        pump.tick(now: 200)

        expect(harness.signals).to include([-pid, "KILL"])

        harness.exits[pid] = 9
        pump.tick(now: 201)
        expect(pump.status).to eq(:stopped)
      end
    end

    context "when immediate stop is requested" do
      let(:immediate) { true }

      it "sends KILL immediately and stops cleanly" do
        pump.start(now: 100)
        pid = harness.last_pid
        stop

        expect(harness.signals.last).to eq([-pid, "KILL"])
        expect(pump.status).to eq(:stopping)

        pump.tick(now: 100.5)
        expect(pump.status).to eq(:stopping)

        harness.exits[pid] = 9
        pump.tick(now: 100.8)
        expect(pump.status).to eq(:stopped)
      end
    end
  end

  describe "#tick" do
    context "when child crashes" do
      it "backs off exponentially and restarts after the delay elapses" do
        pump.start(now: 100)
        harness.exits[harness.last_pid] = 255

        pump.tick(now: 100.5)
        expect(pump.status).to eq(:backoff)

        pump.tick(now: 100.9)
        expect(harness.spawned.size).to eq(1)

        pump.tick(now: 101.6)
        expect(harness.spawned.size).to eq(2)
        expect(pump.status).to eq(:running)
      end

      it "grows the retry delay across repeated failures" do
        pump.start(now: 0)
        [1.0, 2.0, 4.0, 8.0].each_with_index do |delay, round|
          now_time = 0.1 + (round * 100)
          harness.exits[harness.last_pid] = 1
          pump.tick(now: now_time)
          pump.tick(now: now_time + delay)
        end
        expect(harness.spawned.size).to eq(5)
      end

      it "resets backoff attempts once child stays alive past stability window" do
        pump.start(now: 0)
        harness.exits[harness.last_pid] = 1
        pump.tick(now: 1)
        pump.tick(now: 2)

        harness.exits[harness.last_pid] = 1
        pump.tick(now: 2.5)
        pump.tick(now: 4.5)

        pump.tick(now: 500) # Past STABLE_AFTER window
        harness.exits[harness.last_pid] = 1
        pump.tick(now: 501)

        pump.tick(now: 501.9)
        expect(harness.spawned.size).to eq(3)
        pump.tick(now: 502.1)
        expect(harness.spawned.size).to eq(4)
      end

      it "emits exited events tagged with camera and role" do
        pump.start(now: 100)
        harness.exits[harness.last_pid] = 3
        pump.tick(now: 100.5)

        crash_event = events.find { |e| e[:event] == :exited }
        expect(crash_event).to include(camera: "front", role: :sub, intentional: false)
      end
    end

    context "when stderr contains error details" do
      before do
        harness.spawn_stderr = "Error opening 'rtsp://admin:supersecret@10.0.0.5/stream2': Connection refused\n"
      end

      it "surfaces the newest stderr line and sanitizes embedded passwords" do
        pump.start(now: 100)
        harness.exits[harness.last_pid] = 1
        pump.tick(now: 101.5)

        expect(pump.last_error).to include("ffmpeg exited with code 1")
        expect(pump.last_error).to include("rtsp://admin:***@10.0.0.5/stream2")
        expect(pump.last_error).not_to include("supersecret")
      end
    end

    context "when unconfigured camera retries" do
      let(:secrets) { Fakes::Secrets.new("front" => nil) }

      it "retries on long timer and starts spawning once credentials exist" do
        pump.start(now: 0)
        pump.tick(now: described_class::UNCONFIGURED_RETRY - 1)
        expect(harness.spawned).to be_empty

        secrets.reveal!("front", "late")
        pump.tick(now: described_class::UNCONFIGURED_RETRY + 1)
        expect(harness.spawned.size).to eq(1)
      end
    end
  end

  describe "#wanted?" do
    subject(:wanted?) { pump.wanted? }

    context "when pump has not been started" do
      it "returns false" do
        expect(wanted?).to be false
      end
    end

    context "when pump has been started" do
      before { pump.start(now: 0) }

      it "returns true" do
        expect(wanted?).to be true
      end
    end
  end

  describe "#frame_path" do
    subject(:frame_path) { pump.frame_path }

    it "returns the expected jpeg output path in runtime_dir" do
      expect(frame_path).to eq(File.join(runtime_dir, "front.jpg"))
    end
  end

  describe "#running?" do
    subject(:running?) { pump.running? }

    context "when pump is idle" do
      it "returns false" do
        expect(running?).to be false
      end
    end

    context "when pump has started" do
      before { pump.start(now: 0) }

      it "returns true" do
        expect(running?).to be true
      end
    end
  end

  describe "#status" do
    subject(:status) { pump.status }

    context "when initialized" do
      it "returns :idle" do
        expect(status).to eq(:idle)
      end
    end

    context "when started" do
      before { pump.start(now: 0) }

      it "returns :running" do
        expect(status).to eq(:running)
      end
    end
  end

  describe "#last_error" do
    subject(:last_error) { pump.last_error }

    context "when no error has occurred" do
      it "returns nil" do
        expect(last_error).to be_nil
      end
    end
  end

  describe "#input_strategy" do
    subject(:input_strategy) { default_pump.input_strategy }

    let(:default_pump) do
      described_class.new(
        camera:, role: :sub, runtime_dir:, fps: 5, hwaccel: true,
        secrets:, spawner: harness.spawner, reaper: harness.reaper, killer: harness.killer
      )
    end

    context "when not explicitly configured" do
      it "defaults to argv" do
        expect(input_strategy).to eq(:argv)
      end
    end
  end
end
