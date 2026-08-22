# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'
require 'fileutils'

RSpec.describe VisionHub::FramePump do
  subject(:pump) do
    build_pump(role: role, fps: fps, hwaccel: hwaccel, input_strategy: input_strategy, secrets: secrets)
  end

  let(:camera) do
    VisionHub::Camera.from_hash({ 'id' => 'front', 'host' => '10.0.0.5', 'username' => 'admin' }, 0)
  end
  let(:role) { :sub }
  let(:fps) { 5 }
  let(:hwaccel) { true }
  let(:input_strategy) { :argv }
  let(:secrets) { Fakes::Secrets.new('front' => 'pw') }
  let(:events) { [] }

  # ---- fake process machinery -------------------------------------------------
  let(:runtime_dir) { Dir.mktmpdir }
  let(:spawned) { [] }          # argv arrays, one per spawn
  let(:live) { {} }             # pid => true while the child has not exited
  let(:pid_counter) { [4000] }  # last issued pid
  let(:exits) { {} }            # pid => exit code to report on next reap
  let(:signals) { [] }          # [target, name]
  let(:stderr_text) { '' }

  let(:spawner) do
    lambda do |argv|
      pid_counter[0] += 1
      pid = pid_counter[0]
      spawned << argv.dup
      live[pid] = true
      [pid, StringIO.new(stderr_text.dup)]
    end
  end
  let(:spawner_with_stderr) do
    lambda do |argv|
      pid_counter[0] += 1
      pid = pid_counter[0]
      spawned << argv.dup
      live[pid] = true
      [pid, StringIO.new("some earlier warning\nConnection refused\n")]
    end
  end
  let(:reaper) do
    lambda do |pid, _flags|
      return nil unless exits.key?(pid)

      code = exits.delete(pid)
      live.delete(pid)
      [pid, Fakes::Status.new(code)]
    end
  end
  let(:killer) do
    lambda do |target, name|
      signals << [target, name]
      live.key?(target.abs)
    end
  end

  def build_pump(role:, fps:, hwaccel:, input_strategy:, secrets:)
    described_class.new(
      camera: camera, role: role, runtime_dir: runtime_dir, fps: fps, hwaccel: hwaccel,
      input_strategy: input_strategy, secrets: secrets,
      spawner: spawner, reaper: reaper, killer: killer
    ).on_event { |payload| events << payload }
  end

  def backoff_due_at(now)
    pump.instance_variable_get(:@next_action_at) - now
  end

  after { FileUtils.remove_entry(runtime_dir) if File.directory?(runtime_dir) }

  describe '#build_argv (argv strategy)' do
    it 'passes the URL directly and forces TCP with a socket timeout' do
      argv = pump.build_argv('rtsp://u:p@h/s')

      expect(argv[argv.index('-i') + 1]).to eq('rtsp://u:p@h/s')
      expect(argv[argv.index('-timeout') + 1]).to eq(described_class::RTSP_TIMEOUT_US.to_s)
      expect(argv).not_to include('-f')
    end

    it 'targets one shared JPEG per camera with snapshot mode for sub role' do
      argv = pump.build_argv('rtsp://u:p@h/s')

      expect(argv).to end_with(File.join(runtime_dir, 'front.jpg'))
      expect(argv).to include('-frames:v', '1', '-y', '-atomic_writing', '1')
      expect(argv[argv.index('-vf') + 1]).to eq('scale=640:-1')
      expect(argv).to include('-hwaccel', 'auto')
    end

    it 'targets continuous streaming for main role with configured fps' do
      main_pump = build_pump(role: :main, fps: 20, hwaccel: true, input_strategy: :argv, secrets: secrets)
      argv = main_pump.build_argv('rtsp://u:p@h/s')

      expect(argv).to end_with(File.join(runtime_dir, 'front.jpg'))
      expect(argv).to include('-update', '1', '-atomic_writing', '1', '-y')
      expect(argv[argv.index('-vf') + 1]).to eq('fps=20,scale=1280:-1')
      expect(argv).to include('-hwaccel', 'auto')
    end

    context 'with hwaccel disabled' do
      let(:hwaccel) { false }

      it 'omits hardware decode flags' do
        expect(pump.build_argv('rtsp://u:p@h/s')).not_to include('-hwaccel')
      end
    end

    context 'with the concat_file strategy' do
      let(:input_strategy) { :concat_file }

      it 'writes a 0600 playlist and keeps the credential out of argv' do
        argv = pump.build_argv('rtsp://admin:s3cret@10.0.0.5/stream2')

        playlist = File.join(runtime_dir, 'front.sub.ffconcat')
        expect(argv).to include(playlist)
        expect(argv.join(' ')).not_to include('s3cret')
        expect(format('%o', File.stat(playlist).mode)).to end_with('600')
        expect(File.read(playlist)).to include("file 'rtsp://admin:s3cret@10.0.0.5/stream2'")
      end

      it 'escapes single quotes in the URL' do
        pump.build_argv("rtsp://a:b'c@d/s")

        expect(File.read(File.join(runtime_dir, 'front.sub.ffconcat'))).to include("b''c")
      end
    end
  end

  describe 'start / stop lifecycle' do
    it 'spawns ffmpeg once and reports running' do
      pump.start(now: 100)

      expect(spawned.size).to eq(1)
      expect(pump.status).to eq(:running)
      expect(events.map { |e| e[:event] }).to eq([:started])
    end

    it 'ignores start() while running or backing off' do
      pump.start(now: 100)
      exits[pid_counter[0]] = 1
      pump.tick(now: 101)

      pump.start(now: 102)
      pump.start(now: 103)

      expect(spawned.size).to eq(1)
    end

    it 'uses the mainstream URL for the main role' do
      main_pump = build_pump(role: :main, fps: 10, hwaccel: true, input_strategy: :argv,
                             secrets: Fakes::Secrets.new('front' => 'pw'))
      main_pump.start(now: 100)

      url = spawned[0][spawned[0].index('-i') + 1]
      expect(url).to end_with('/stream1')
      expect(url).to include('admin:pw@')
    end

    it 'stops gracefully: TERM then confirmation via the reaper' do
      pump.start(now: 100)
      pump.stop(now: 100)

      expect(signals.last).to eq([-pid_counter[0], 'TERM'])
      expect(pump.status).to eq(:stopping)

      exits[pid_counter[0]] = 0
      pump.tick(now: 101)

      expect(pump.status).to eq(:stopped)
      expect(pump.running?).to be(false)
    end

    it 'escalates to KILL once TERM goes unanswered past the grace period' do
      pump.start(now: 100)
      pid = pid_counter[0]
      pump.stop(now: 100)
      pump.tick(now: 200)

      expect(signals).to include([-pid, 'KILL'])

      exits[pid] = 9
      pump.tick(now: 201)
      expect(pump.status).to eq(:stopped)
    end
  end

  describe 'crash handling and backoff' do
    it 'backs off exponentially and restarts only after the delay elapses' do
      pump.start(now: 100)
      exits[pid_counter[0]] = 255

      pump.tick(now: 100.5)
      expect(pump.status).to eq(:backoff)

      pump.tick(now: 100.9)
      expect(spawned.size).to eq(1)

      pump.tick(now: 101.6)
      expect(spawned.size).to eq(2)
      expect(pump.status).to eq(:running)
    end

    it 'grows the delay up to the cap across repeated failures' do
      delays = []
      pump.start(now: 0)
      4.times do |round|
        now = 0.1 + (round * 100)
        exits[pid_counter[0]] = 1
        pump.tick(now: now)
        delays << backoff_due_at(now).round(6)
        pump.tick(now: now + 61) # always past due → respawn
      end

      expect(delays).to eq([1.0, 2.0, 4.0, 8.0])
    end

    it 'resets attempts once a child stayed alive past the stability window' do
      pump.start(now: 0)
      exits[pid_counter[0]] = 1
      pump.tick(now: 1)   # crash 1 → 1s backoff
      pump.tick(now: 2)   # respawn

      exits[pid_counter[0]] = 1
      pump.tick(now: 2.5) # crash 2 → grown backoff
      grown_backoff = backoff_due_at(2.5)

      pump.tick(now: 5)   # respawn
      pump.tick(now: 500) # alive well past STABLE_AFTER → attempts forgotten
      exits[pid_counter[0]] = 1
      pump.tick(now: 501)

      expect(grown_backoff).to eq(2.0)
      expect(backoff_due_at(501)).to eq(1.0)
    end

    it 'surfaces the newest stderr line as error detail' do
      pump_with_stderr = described_class.new(
        camera: camera, role: :sub, runtime_dir: runtime_dir, fps: 5, hwaccel: true,
        input_strategy: :argv, secrets: secrets, spawner: spawner_with_stderr,
        reaper: reaper, killer: killer
      )

      pump_with_stderr.start(now: 100)
      exits[pid_counter[0]] = 1
      pump_with_stderr.tick(now: 101.5)

      expect(pump_with_stderr.last_error).to include('ffmpeg exited with code 1')
      expect(pump_with_stderr.last_error).to include('Connection refused')
    end

    it 'emits exited events tagged with camera and role' do
      pump.start(now: 100)
      exits[pid_counter[0]] = 3
      pump.tick(now: 100.5)

      crash_event = events.find { |e| e[:event] == :exited }
      expect(crash_event).to include(camera: 'front', role: :sub, intentional: false)
    end
  end

  describe 'unconfigured cameras' do
    let(:secrets) { Fakes::Secrets.new }

    it 'does not spawn, reports unconfigured, and retries on a long timer' do
      pump.start(now: 100)

      expect(spawned).to be_empty
      expect(pump.status).to eq(:unconfigured)
      expect(events.last[:event]).to eq(:unconfigured)

      pump.tick(now: described_class::UNCONFIGURED_RETRY + 99)
      pump.tick(now: described_class::UNCONFIGURED_RETRY + 101)

      expect(spawned).to be_empty
      expect(pump.status).to eq(:unconfigured)
    end

    it 'starts spawning as soon as the keyring entry exists' do
      store = Fakes::Secrets.new('front' => nil)
      pump = build_pump(role: :sub, fps: 5, hwaccel: true, input_strategy: :argv, secrets: store)

      pump.start(now: 0)
      store.reveal!('front', 'late')
      pump.tick(now: described_class::UNCONFIGURED_RETRY + 1)

      expect(spawned.size).to eq(1)
    end
  end

  describe 'anonymous cameras' do
    let(:camera) { VisionHub::Camera.from_hash({ 'id' => 'anon', 'host' => '10.0.0.9' }, 0) }
    let(:secrets) do
      store = instance_double(VisionHub::SecretStore)
      allow(store).to receive(:lookup).and_raise(RuntimeError, 'must never be called')
      store
    end

    it 'spawns without consulting the keyring' do
      pump.start(now: 0)

      expect(spawned.size).to eq(1)
      expect(spawned[0].join(' ')).to include('rtsp://10.0.0.9:554/stream2')
    end
  end
end
