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

  it 'caches both hits and misses across repeated lookups' do
    lookup_result.replace([true, 'pw', ''])
    store.lookup('front')

    lookup_result.replace([false, '', ''])
    expect(store.lookup('front')).to eq('pw')
    expect(store.lookup('garage')).to be_nil
    expect(calls.size).to eq(2)
  end

  it 're-queries after clear_cache!' do
    lookup_result.replace([true, 'old', ''])
    store.lookup('front')

    lookup_result.replace([true, 'new', ''])
    store.clear_cache!

    expect(store.lookup('front')).to eq('new')
  end

  it 'builds a store hint containing attributes but no secret material' do
    command = store.store_command_for('front')

    expect(command).to include("secret-tool store --label='VisionHub camera front'")
    expect(command).to include('application tobiasz-p.vision-hub camera front')
    expect(command).not_to include('s3cret')
  end
end
