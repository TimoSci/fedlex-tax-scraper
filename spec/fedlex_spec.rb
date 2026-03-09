# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Fedlex' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
    Log.setup
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  def sparql_json_response(url_value)
    {
      'results' => {
        'bindings' => [
          { 'url' => { 'value' => url_value } }
        ]
      }
    }.to_json
  end

  def empty_sparql_response
    { 'results' => { 'bindings' => [] } }.to_json
  end

  describe '.current_html_url' do
    it 'returns the HTML URL from a SPARQL response' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: sparql_json_response('https://www.fedlex.admin.ch/eli/cc/1991/1184/de/html'))

      result = Fedlex.current_html_url('https://fedlex.data.admin.ch/eli/cc/1991/1184_1184_1184')
      expect(result).to eq('https://www.fedlex.admin.ch/eli/cc/1991/1184/de/html')
    end

    it 'returns nil when no bindings are returned' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: empty_sparql_response)

      result = Fedlex.current_html_url('https://fedlex.data.admin.ch/eli/cc/nonexistent')
      expect(result).to be_nil
    end

    it 'returns nil and logs a warning on SPARQL failure' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 500, body: 'error')

      allow_any_instance_of(Object).to receive(:sleep)
      expect { Fedlex.current_html_url('https://fedlex.data.admin.ch/eli/cc/bad') }
        .to output(/SPARQL lookup failed/).to_stdout
    end
  end

  describe '.current_pdf_url' do
    it 'returns the PDF URL from a SPARQL response' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: sparql_json_response('https://www.fedlex.admin.ch/eli/cc/1991/1184/de/pdf-a'))

      result = Fedlex.current_pdf_url('https://fedlex.data.admin.ch/eli/cc/1991/1184_1184_1184')
      expect(result).to eq('https://www.fedlex.admin.ch/eli/cc/1991/1184/de/pdf-a')
    end

    it 'returns nil when no bindings are returned' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: empty_sparql_response)

      result = Fedlex.current_pdf_url('https://fedlex.data.admin.ch/eli/cc/nonexistent')
      expect(result).to be_nil
    end

    it 'returns nil on failure without raising' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 500, body: 'error')

      allow_any_instance_of(Object).to receive(:sleep)
      result = Fedlex.current_pdf_url('https://fedlex.data.admin.ch/eli/cc/bad')
      expect(result).to be_nil
    end
  end

  describe '.discover_tax_laws' do
    it 'returns an array of discovered law hashes' do
      response_body = {
        'results' => {
          'bindings' => [
            {
              'work' => { 'value' => 'https://fedlex.data.admin.ch/eli/cc/2009/615' },
              'rsNumber' => { 'value' => '641.20' },
              'titleDe' => { 'value' => 'Mehrwertsteuergesetz' }
            },
            {
              'work' => { 'value' => 'https://fedlex.data.admin.ch/eli/cc/1991/1184_1184_1184' },
              'rsNumber' => { 'value' => '642.11' },
              'titleDe' => { 'value' => 'DBG' }
            }
          ]
        }
      }.to_json

      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: response_body)

      results = Fedlex.discover_tax_laws
      expect(results.length).to eq(2)
      expect(results.first['work_uri']).to eq('https://fedlex.data.admin.ch/eli/cc/2009/615')
      expect(results.first['sr']).to eq('641.20')
      expect(results.first['title']).to eq('Mehrwertsteuergesetz')
    end

    it 'uses "(no title)" when titleDe is missing' do
      response_body = {
        'results' => {
          'bindings' => [
            {
              'work' => { 'value' => 'https://fedlex.data.admin.ch/eli/cc/2009/615' },
              'rsNumber' => { 'value' => '641.20' }
            }
          ]
        }
      }.to_json

      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 200, body: response_body)

      results = Fedlex.discover_tax_laws
      expect(results.first['title']).to eq('(no title)')
    end

    it 'returns empty array on failure' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparql/)
        .to_return(status: 500, body: 'error')

      allow_any_instance_of(Object).to receive(:sleep)
      results = Fedlex.discover_tax_laws
      expect(results).to eq([])
    end
  end
end
