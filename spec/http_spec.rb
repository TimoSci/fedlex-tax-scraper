# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'HTTP' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
    Log.setup
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.get' do
    it 'returns the response body on HTTP 200' do
      stub_request(:get, 'https://example.com/page')
        .to_return(status: 200, body: 'Hello World')

      result = HTTP.get('https://example.com/page')
      expect(result).to eq('Hello World')
    end

    it 'sets the correct User-Agent header' do
      stub_request(:get, 'https://example.com/page')
        .with(headers: { 'User-Agent' => 'FedlexTaxScraper/1.0 (educational; contact: scraper@example.com)' })
        .to_return(status: 200, body: 'ok')

      HTTP.get('https://example.com/page')
    end

    it 'follows redirects (301, 302, 307)' do
      stub_request(:get, 'https://example.com/old')
        .to_return(status: 302, headers: { 'Location' => 'https://example.com/new' })
      stub_request(:get, 'https://example.com/new')
        .to_return(status: 200, body: 'redirected')

      result = HTTP.get('https://example.com/old')
      expect(result).to eq('redirected')
    end

    it 'raises on non-200 responses after retries' do
      stub_request(:get, 'https://example.com/fail')
        .to_return(status: 500, body: 'error')

      allow_any_instance_of(Object).to receive(:sleep)
      expect { HTTP.get('https://example.com/fail') }.to raise_error(/HTTP 500/)
    end

    it 'retries on transient errors' do
      call_count = 0
      stub_request(:get, 'https://example.com/flaky')
        .to_return do
          call_count += 1
          if call_count < 3
            raise Errno::ECONNRESET
          else
            { status: 200, body: 'ok' }
          end
        end

      allow_any_instance_of(Object).to receive(:sleep)
      result = HTTP.get('https://example.com/flaky')
      expect(result).to eq('ok')
    end

    it 'uses custom Accept header when provided' do
      stub_request(:get, 'https://example.com/sparql')
        .with(headers: { 'Accept' => 'application/sparql-results+json' })
        .to_return(status: 200, body: '{"results":{}}')

      result = HTTP.get('https://example.com/sparql', accept: 'application/sparql-results+json')
      expect(result).to eq('{"results":{}}')
    end

    it 'handles rate limiting (429) with Retry-After' do
      call_count = 0
      stub_request(:get, 'https://example.com/ratelimit')
        .to_return do
          call_count += 1
          if call_count == 1
            { status: 429, headers: { 'Retry-After' => '1' }, body: '' }
          else
            { status: 200, body: 'ok' }
          end
        end

      allow_any_instance_of(Object).to receive(:sleep)
      result = HTTP.get('https://example.com/ratelimit')
      expect(result).to eq('ok')
    end
  end
end
