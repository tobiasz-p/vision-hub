# frozen_string_literal: true

require 'spec_helper'
require 'vision_hub/camera'
require 'vision_hub/audio_pump'

RSpec.describe VisionHub::AudioPump do
  subject(:pump) do
    described_class.new(
      camera: camera, secrets: secrets,
      spawner: spawner, reaper: reaper, killer: killer
    ).on_event { |payload| events << payload }
  end

  let(:camera) do
    VisionHub::Camera.from_hash(
      {
        'id' => 'front', 'name' => 'Front Gate', 'host' => 'cam.local',
        'username' => 'admin', 'mainPath' => '/main', 'subPath' => '/sub'
      }, 0
    )
  end
  let(:secrets) { Fakes::Secrets.new('front' => 'secret123') }
  let(:events) { [] }
  let(:signals) { [] }
  let(:live) { {} }
  let(:spawner) do
    lambda do |argv|
      pid = live.size + 100
      live[pid] = { argv: argv }
      pid
    end
  end
  let(:reaper) do
    lambda do |target_pid, _block|
      pid = target_pid || live.keys.first
      return nil unless pid && live[pid]&.key?(:exit_code)

      code = live[pid][:exit_code]
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

  describe '#build_argv' do
    it 'constructs headless audio playback command using ffplay' do
      argv = pump.build_argv('rtsp://admin:secret123@cam.local:554/main')

      expect(argv).to include('ffplay', '-nodisp', '-autoexit', '-vn', '-sn', '-rtsp_transport', 'tcp')
      expect(argv.last).to eq('rtsp://admin:secret123@cam.local:554/main')
    end
  end

  describe '#start and #stop' do
    it 'spawns player on start and signals on stop' do
      pump.start(now: 10)
      expect(pump).to be_running
      expect(events).to include(hash_including(event: :started))

      pump.stop(now: 15)
      expect(pump).not_to be_running
      expect(signals).to include([-100, 'TERM'])
      expect(events).to include(hash_including(event: :stopped))
    end

    it 'reports unconfigured when credentials are missing' do
      empty_secrets = Fakes::Secrets.new
      unauth_pump = described_class.new(
        camera: camera, secrets: empty_secrets,
        spawner: spawner, reaper: reaper, killer: killer
      ).on_event { |payload| events << payload }

      unauth_pump.start(now: 10)
      expect(unauth_pump.status).to eq(:unconfigured)
      expect(events).to include(hash_including(event: :unconfigured))
    end
  end
end
