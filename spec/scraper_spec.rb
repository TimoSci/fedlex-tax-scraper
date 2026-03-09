# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Scraper' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  def sparql_html_response(url)
    { 'results' => { 'bindings' => [{ 'url' => { 'value' => url } }] } }.to_json
  end

  def empty_sparql_response
    { 'results' => { 'bindings' => [] } }.to_json
  end

  def sample_law_html
    <<~HTML
      <html><body><article>
        <h1>Testgesetz</h1>
        <p>Art. 1 Dies ist ein Testgesetz.</p>
        <p>Art. 2 Weitere Bestimmungen.</p>
      </article></body></html>
    HTML
  end

  describe '#initialize' do
    it 'creates the laws directory' do
      Scraper.new
      expect(Dir.exist?(File.join(tmp_dir, 'laws'))).to be true
    end

    it 'loads state' do
      existing = { 'completed' => ['DBG'], 'failed' => {}, 'started_at' => Time.now.iso8601 }
      FileUtils.mkdir_p(tmp_dir)
      File.write(File.join(tmp_dir, 'state.json'), JSON.generate(existing))

      expect { Scraper.new }.to output(/Already completed: 1 laws/).to_stdout
    end
  end

  describe '#build_header (via send)' do
    it 'builds a formatted header string' do
      scraper = Scraper.new
      header = scraper.send(:build_header, 'DBG', '642.11', 'Bundessteuer', 'https://example.com')
      expect(header).to include('LAW: DBG')
      expect(header).to include('SR:  642.11')
      expect(header).to include('TITLE: Bundessteuer')
      expect(header).to include('SOURCE: https://example.com')
      expect(header).to include('SCRAPED:')
      expect(header).to include('=' * 80)
    end
  end

  describe '#safe_filename (via send)' do
    it 'replaces special characters with underscores' do
      scraper = Scraper.new
      expect(scraper.send(:safe_filename, 'CO2-Gesetz')).to eq('CO2-Gesetz')
      expect(scraper.send(:safe_filename, 'MWSTV-EFD')).to eq('MWSTV-EFD')
      expect(scraper.send(:safe_filename, 'SR 641.20')).to eq('SR_641.20')
      expect(scraper.send(:safe_filename, 'a/b:c')).to eq('a_b_c')
    end
  end

  describe '#process_law (via send)' do
    it 'skips already completed laws' do
      existing = { 'completed' => ['DBG'], 'failed' => {}, 'started_at' => Time.now.iso8601 }
      FileUtils.mkdir_p(tmp_dir)
      File.write(File.join(tmp_dir, 'state.json'), JSON.generate(existing))

      scraper = Scraper.new
      law = { name: 'DBG', sr: '642.11', cc: '1991/1184_1184_1184', description: 'Test' }

      expect { scraper.send(:process_law, law) }.to output(/SKIP.*DBG/).to_stdout
    end

    it 'fetches, extracts, and saves law text' do
      # Stub SPARQL lookup
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return(
          { status: 200, body: sparql_html_response('https://www.fedlex.admin.ch/eli/cc/test/de/html') },
          { status: 200, body: empty_sparql_response }
        )

      # Stub HTML fetch
      stub_request(:get, 'https://www.fedlex.admin.ch/eli/cc/test/de/html')
        .to_return(status: 200, body: sample_law_html)

      scraper = Scraper.new
      law = { name: 'TestLaw', sr: '999.99', cc: 'test', description: 'Test law' }

      scraper.send(:process_law, law)

      output_file = File.join(tmp_dir, 'laws', 'TestLaw.txt')
      expect(File.exist?(output_file)).to be true

      content = File.read(output_file)
      expect(content).to include('LAW: TestLaw')
      expect(content).to include('Testgesetz')
      expect(content).to include('Art. 1 Dies ist ein Testgesetz.')
    end

    it 'marks the law as failed when text extraction returns empty' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return(status: 200, body: empty_sparql_response)

      scraper = Scraper.new
      law = { name: 'EmptyLaw', sr: '000.00', cc: 'empty', description: 'Empty' }

      scraper.send(:process_law, law)

      state = JSON.parse(File.read(File.join(tmp_dir, 'state.json')))
      expect(state['failed']).to have_key('EmptyLaw')
    end
  end

  describe '#compile_master_file (via send)' do
    it 'compiles all law .txt files into one master file' do
      laws_dir = File.join(tmp_dir, 'laws')
      FileUtils.mkdir_p(laws_dir)

      File.write(File.join(laws_dir, 'AAA.txt'), "Law A content")
      File.write(File.join(laws_dir, 'BBB.txt'), "Law B content")

      scraper = Scraper.new
      scraper.send(:compile_master_file)

      master = File.join(tmp_dir, 'swiss_federal_tax_laws_FULLTEXT.txt')
      expect(File.exist?(master)).to be true

      content = File.read(master)
      expect(content).to include('SWISS FEDERAL TAX LAWS')
      expect(content).to include('TABLE OF CONTENTS')
      expect(content).to include('AAA')
      expect(content).to include('BBB')
      expect(content).to include('Law A content')
      expect(content).to include('Law B content')
      expect(content).to include('Laws included: 2')
    end

    it 'handles empty laws directory' do
      scraper = Scraper.new
      scraper.send(:compile_master_file)

      master = File.join(tmp_dir, 'swiss_federal_tax_laws_FULLTEXT.txt')
      expect(File.exist?(master)).to be true
      content = File.read(master)
      expect(content).to include('Laws included: 0')
    end
  end

  describe '#fetch_law_text (via send)' do
    it 'prefers HTML when available' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return(status: 200, body: sparql_html_response('https://www.fedlex.admin.ch/test.html'))

      stub_request(:get, 'https://www.fedlex.admin.ch/test.html')
        .to_return(status: 200, body: sample_law_html)

      scraper = Scraper.new
      text = scraper.send(:fetch_law_text, 'Test', '999', 'https://fedlex.data.admin.ch/eli/cc/test')
      expect(text).to include('Testgesetz')
    end

    it 'falls back to PDF lookup when HTML is empty' do
      html_sparql = sparql_html_response('https://www.fedlex.admin.ch/empty.html')
      pdf_sparql = sparql_html_response('https://www.fedlex.admin.ch/test.pdf')

      call_count = 0
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return do
          call_count += 1
          if call_count == 1
            { status: 200, body: html_sparql }
          else
            { status: 200, body: pdf_sparql }
          end
        end

      stub_request(:get, 'https://www.fedlex.admin.ch/empty.html')
        .to_return(status: 200, body: '<html><body></body></html>')

      stub_request(:get, 'https://www.fedlex.admin.ch/test.pdf')
        .to_return(status: 200, body: '%PDF-1.4 fake pdf')

      scraper = Scraper.new
      text = scraper.send(:fetch_law_text, 'Test', '999', 'https://fedlex.data.admin.ch/eli/cc/test')
      expect(text).to include('PDF available at')
    end

    it 'returns nil when neither HTML nor PDF is available' do
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return(status: 200, body: empty_sparql_response)

      scraper = Scraper.new
      text = scraper.send(:fetch_law_text, 'Test', '999', 'https://fedlex.data.admin.ch/eli/cc/test')
      expect(text).to be_nil
    end
  end

  describe '#run' do
    it 'processes known laws and runs discovery' do
      Object.send(:remove_const, :KNOWN_LAWS)
      Object.const_set(:KNOWN_LAWS, [
        { name: 'TestOnly', sr: '999.99', cc: 'test/only', description: 'Test' }
      ].freeze)

      html_response = sparql_html_response('https://www.fedlex.admin.ch/test.html')
      discovery_response = { 'results' => { 'bindings' => [] } }.to_json

      call_count = 0
      stub_request(:get, /fedlex\.data\.admin\.ch\/sparqlendpoint/)
        .to_return do
          call_count += 1
          if call_count == 1
            { status: 200, body: html_response }
          else
            { status: 200, body: discovery_response }
          end
        end

      stub_request(:get, 'https://www.fedlex.admin.ch/test.html')
        .to_return(status: 200, body: sample_law_html)

      scraper = Scraper.new
      scraper.run

      expect(File.exist?(File.join(tmp_dir, 'laws', 'TestOnly.txt'))).to be true
      expect(File.exist?(File.join(tmp_dir, 'swiss_federal_tax_laws_FULLTEXT.txt'))).to be true
    end
  end
end
