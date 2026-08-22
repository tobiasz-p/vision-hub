# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VisionHub::SecretStore do
  subject(:store) { described_class.new(application_id: 'tobiasz-p.vision-hub', runner: runner) }

  let(:calls) { [] }
  let(:lookup_result) { [true, '', ''] }
  let(:runner) do
    lambda do |argv|
      calls << argv
      lookup_result
    end
  end

  it 'looks a password up with attribute-style arguments' do
    lookup_result.replace([true, "s3cret\n", ''])

    expect(store.lookup('front')).to eq('s3cret')
    expect(calls.last).to eq(['secret-tool', 'lookup', 'application', 'tobiasz-p.vision-hub', 'camera', 'front'])
  end

  it 'returns nil when the keyring has no entry' do
    lookup_result.replace([false, '', 'No result'])

    expect(store.lookup('front')).to be_nil
  end

  it 'treats an empty stdout as missing even on success' do
    lookup_result.replace([true, "\n", ''])

    expect(store.lookup('front')).to be_nil
  end

  it 'caches hits but re-asks misses so later keyring entries are found' do
    lookup_result.replace([true, 'pw', ''])
    expect(store.lookup('front')).to eq('pw')

    lookup_result.replace([false, '', ''])
    expect(store.lookup('front')).to eq('pw') # cached hit, no new call
    expect(store.lookup('garage')).to be_nil
    expect(calls.size).to eq(3) # 'front', 'garage', and fallback 'default'

    # The user adds the missing entry; the next retry must see it.
    lookup_result.replace([true, 'late', ''])
    expect(store.lookup('garage')).to eq('late')
    expect(calls.size).to eq(4)
  end

  it 're-queries after clear_cache!' do
    lookup_result.replace([true, 'old', ''])
    store.lookup('front')

    lookup_result.replace([true, 'new', ''])
    store.clear_cache!

    expect(store.lookup('front')).to eq('new')
  end

  it 'falls back to default camera secret when specific camera is not in keyring' do
    lookup_map = { 'default' => [true, 'shared_pass', ''] }
    custom_runner = lambda do |argv|
      cam = argv[argv.index('camera') + 1]
      lookup_map[cam] || [false, '', 'No result']
    end
    store = described_class.new(application_id: 'tobiasz-p.vision-hub', runner: custom_runner)

    expect(store.lookup('cam2')).to eq('shared_pass')
  end

  it 'builds a store hint containing attributes but no secret material' do
    command = store.store_command_for('front')

    expect(command).to include("secret-tool store --label='VisionHub camera front'")
    expect(command).to include('application tobiasz-p.vision-hub camera front')
    expect(command).not_to include('s3cret')
  end
end
