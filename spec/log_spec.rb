# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Log' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    # Clean slate: undefine constants if they exist from a previous spec
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.setup' do
    it 'creates the output directory and log file' do
      Log.setup
      expect(Dir.exist?(tmp_dir)).to be true
    end
  end

  describe '.write' do
    before { Log.setup }

    it 'writes a formatted log line to stdout and the log file' do
      expect { Log.write('info', 'test message') }.to output(/\[INFO \] test message/).to_stdout
      log_content = File.read(File.join(tmp_dir, 'scraper.log'))
      expect(log_content).to include('test message')
      expect(log_content).to match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/)
    end

    it 'uppercases and left-justifies the log level' do
      expect { Log.write('warn', 'x') }.to output(/\[WARN \]/).to_stdout
    end
  end

  describe 'convenience methods' do
    before { Log.setup }

    it '.info writes at INFO level' do
      expect { Log.info('hi') }.to output(/\[INFO \]/).to_stdout
    end

    it '.warn writes at WARN level' do
      expect { Log.warn('caution') }.to output(/\[WARN \]/).to_stdout
    end

    it '.error writes at ERROR level' do
      expect { Log.error('bad') }.to output(/\[ERROR\]/).to_stdout
    end

    it '.ok writes at OK level' do
      expect { Log.ok('good') }.to output(/\[OK   \]/).to_stdout
    end
  end
end
