# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'State' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
    Log.setup
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.load' do
    it 'returns a fresh state when no state file exists' do
      state = State.load
      expect(state['completed']).to eq([])
      expect(state['failed']).to eq({})
      expect(state).to have_key('started_at')
    end

    it 'loads existing state from file' do
      existing = { 'completed' => ['DBG'], 'failed' => {}, 'started_at' => '2025-01-01T00:00:00+00:00' }
      File.write(File.join(tmp_dir, 'state.json'), JSON.generate(existing))
      state = State.load
      expect(state['completed']).to eq(['DBG'])
    end

    it 'returns fresh state when state file is corrupted JSON' do
      File.write(File.join(tmp_dir, 'state.json'), '{{not json}}')
      expect { State.load }.to output(/corrupted/).to_stdout
    end
  end

  describe '.save' do
    it 'persists state to disk as JSON' do
      state = { 'completed' => ['X'], 'failed' => {} }
      State.save(state)
      raw = File.read(File.join(tmp_dir, 'state.json'))
      parsed = JSON.parse(raw)
      expect(parsed['completed']).to eq(['X'])
    end
  end

  describe '.completed?' do
    it 'returns true for completed laws' do
      state = { 'completed' => ['DBG'] }
      expect(State.completed?(state, 'DBG')).to be true
    end

    it 'returns false for incomplete laws' do
      state = { 'completed' => [] }
      expect(State.completed?(state, 'DBG')).to be false
    end
  end

  describe '.mark_complete' do
    it 'adds the law to completed and removes from failed' do
      state = { 'completed' => [], 'failed' => { 'DBG' => ['error'] } }
      State.mark_complete(state, 'DBG')
      expect(state['completed']).to include('DBG')
      expect(state['failed']).not_to have_key('DBG')
    end

    it 'does not duplicate entries' do
      state = { 'completed' => ['DBG'], 'failed' => {} }
      State.mark_complete(state, 'DBG')
      expect(state['completed'].count('DBG')).to eq(1)
    end

    it 'saves state to disk' do
      state = { 'completed' => [], 'failed' => {} }
      State.mark_complete(state, 'X')
      expect(File.exist?(File.join(tmp_dir, 'state.json'))).to be true
    end
  end

  describe '.mark_failed' do
    it 'records the failure with timestamp and reason' do
      state = { 'completed' => [], 'failed' => {} }
      State.mark_failed(state, 'DBG', 'timeout')
      expect(state['failed']['DBG'].length).to eq(1)
      expect(state['failed']['DBG'].first['reason']).to eq('timeout')
      expect(state['failed']['DBG'].first).to have_key('time')
    end

    it 'appends multiple failures for the same law' do
      state = { 'completed' => [], 'failed' => {} }
      State.mark_failed(state, 'DBG', 'timeout')
      State.mark_failed(state, 'DBG', 'HTTP 500')
      expect(state['failed']['DBG'].length).to eq(2)
    end
  end
end
