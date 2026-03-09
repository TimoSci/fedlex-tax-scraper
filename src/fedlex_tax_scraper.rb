#!/usr/bin/env ruby
# =============================================================================
# fedlex_tax_scraper.rb
#
# Scrapes the full text of all Swiss federal tax laws from fedlex.admin.ch.
# Restartable: tracks progress in a JSON state file and skips already-fetched laws.
# Outputs one .txt file per law, then compiles everything into a single master file.
#
# USAGE:
#   gem install nokogiri          # for HTML parsing
#   ruby fedlex_tax_scraper.rb
#
# Run in background:
#   nohup ruby fedlex_tax_scraper.rb > /dev/null 2>&1 &
#
# Or with screen:
#   screen -S scraper
#   ruby fedlex_tax_scraper.rb
#   Ctrl+A, D   (detach)
#
# OUTPUT:
#   ./output/laws/        — one .txt file per law
#   ./output/scraper.log  — full timestamped log
#   ./output/state.json   — progress tracker (restart-safe)
#   ./output/swiss_federal_tax_laws_FULLTEXT.txt  — compiled master file
# =============================================================================

require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'time'
require 'cgi'

begin
  require 'nokogiri'
rescue LoadError
  puts "ERROR: nokogiri gem not found. Please run: gem install nokogiri"
  exit 1
end

# =============================================================================
# CONFIGURATION
# =============================================================================

OUTPUT_DIR   = File.join(__dir__, 'output')
LAWS_DIR     = File.join(OUTPUT_DIR, 'laws')
LOG_FILE     = File.join(OUTPUT_DIR, 'scraper.log')
STATE_FILE   = File.join(OUTPUT_DIR, 'state.json')
MASTER_FILE  = File.join(OUTPUT_DIR, 'swiss_federal_tax_laws_FULLTEXT.txt')

SPARQL_ENDPOINT = 'https://fedlex.data.admin.ch/sparqlendpoint'
FEDLEX_BASE     = 'https://fedlex.data.admin.ch'

# Delay between HTTP requests (seconds). Be a polite scraper.
REQUEST_DELAY = 2.0

# Max retries per request
MAX_RETRIES = 3

# HTTP timeout (seconds)
HTTP_TIMEOUT = 30

# =============================================================================
# KNOWN LAWS
# Each entry:
#   name:        human-readable short name
#   sr:          Systematische Rechtssammlung number
#   cc:          the "classified collection" path used in Fedlex ELI URIs
#                (eli/cc/{cc}/de)
#   description: brief description
# =============================================================================

KNOWN_LAWS = [
  # --- Direct taxes ---
  {
    name: "DBG",
    sr: "642.11",
    cc: "1991/1184_1184_1184",
    description: "Bundesgesetz über die direkte Bundessteuer"
  },
  {
    name: "DBV",
    sr: "642.118",
    cc: "1993/1341_1341_1341",
    description: "Verordnung über die direkte Bundessteuer"
  },
  {
    name: "Berufskostenverordnung",
    sr: "642.118.1",
    cc: "1993/1346_1346_1346",
    description: "Verordnung über den Abzug der Berufskosten unselbständig Erwerbstätiger"
  },
  {
    name: "EFV",
    sr: "642.116",
    cc: "2019/415",
    description: "Verordnung über den Abzug von Zinsen auf Eigenkapital (Eigenfinanzierungsverordnung)"
  },
  {
    name: "Patentboxverordnung",
    sr: "642.117.1",
    cc: "2019/413",
    description: "Verordnung über die Patentbox"
  },
  {
    name: "Zinssatzverordnung-DBG",
    sr: "642.118.2",
    cc: "2018/781",
    description: "Verordnung über die anwendbaren Zinssätze bei der direkten Bundessteuer"
  },
  {
    name: "StHG",
    sr: "642.14",
    cc: "1991/1256_1256_1256",
    description: "Bundesgesetz über die Harmonisierung der direkten Steuern der Kantone und Gemeinden"
  },
  {
    name: "StHV",
    sr: "642.141",
    cc: "1994/2417_2417_2417",
    description: "Verordnung über die Anwendung des Steuerharmonisierungsgesetzes"
  },

  # --- VAT ---
  {
    name: "MWSTG",
    sr: "641.20",
    cc: "2009/615",
    description: "Bundesgesetz über die Mehrwertsteuer"
  },
  {
    name: "MWSTV",
    sr: "641.201",
    cc: "2009/854",
    description: "Mehrwertsteuerverordnung"
  },
  {
    name: "MWSTV-EFD",
    sr: "641.201.1",
    cc: "2021/714",
    description: "Verordnung des EFD über die Mehrwertsteuer"
  },

  # --- Withholding tax ---
  {
    name: "VStG",
    sr: "642.21",
    cc: "1966/371_385_384",
    description: "Bundesgesetz über die Verrechnungssteuer"
  },
  {
    name: "VStV",
    sr: "642.211",
    cc: "1966/386_400_399",
    description: "Verrechnungssteuerverordnung"
  },

  # --- Stamp duties ---
  {
    name: "StG",
    sr: "641.10",
    cc: "1974/11_11_11",
    description: "Bundesgesetz über die Stempelabgaben"
  },
  {
    name: "StV",
    sr: "641.101",
    cc: "1974/15_15_15",
    description: "Verordnung über die Stempelabgaben"
  },

  # --- Minimum tax (OECD Pillar Two) ---
  {
    name: "EStG",
    sr: "642.23",
    cc: "2023/687",
    description: "Bundesgesetz über die Ergänzungssteuer (Mindestbesteuerungsgesetz)"
  },
  {
    name: "MindStV",
    sr: "642.234",
    cc: "2023/690",
    description: "Mindestbesteuerungsverordnung"
  },

  # --- Special consumption taxes ---
  {
    name: "BierStG",
    sr: "641.411",
    cc: "1998/502_502_502",
    description: "Bundesgesetz über die Biersteuer"
  },
  {
    name: "TbStG",
    sr: "641.31",
    cc: "1969/645_665_649",
    description: "Bundesgesetz über die Tabakbesteuerung"
  },
  {
    name: "TbStV",
    sr: "641.311",
    cc: "1970/210_214_213",
    description: "Verordnung über die Tabakbesteuerung"
  },
  {
    name: "SpiritG",
    sr: "680",
    cc: "2016/188",
    description: "Bundesgesetz über die Besteuerung von Spirituosen"
  },
  {
    name: "MinöStG",
    sr: "641.61",
    cc: "1996/3371_3371_3371",
    description: "Bundesgesetz über die Mineralölsteuer"
  },
  {
    name: "MinöStV",
    sr: "641.611",
    cc: "1997/790_790_790",
    description: "Mineralölsteuerverordnung"
  },
  {
    name: "NSAG",
    sr: "741.71",
    cc: "2012/276",
    description: "Bundesgesetz über die Nationalstrassenabgabe"
  },
  {
    name: "SVAG",
    sr: "641.81",
    cc: "2000/354",
    description: "Bundesgesetz über eine leistungsabhängige Schwerverkehrsabgabe"
  },
  {
    name: "SVAV",
    sr: "641.811",
    cc: "2000/358",
    description: "Verordnung über eine leistungsabhängige Schwerverkehrsabgabe"
  },
  {
    name: "CO2-Gesetz",
    sr: "641.71",
    cc: "2012/855",
    description: "Bundesgesetz über die Reduktion von CO2-Emissionen"
  },

  # --- International tax / administrative assistance ---
  {
    name: "StAhiG",
    sr: "651.1",
    cc: "2013/231",
    description: "Bundesgesetz über die internationale Amtshilfe in Steuersachen"
  },
  {
    name: "StAhiV",
    sr: "651.11",
    cc: "2013/232",
    description: "Verordnung über die internationale Amtshilfe in Steuersachen"
  },
  {
    name: "AIAG",
    sr: "653.1",
    cc: "2016/182",
    description: "Bundesgesetz über den automatischen Informationsaustausch in Steuersachen"
  },
  {
    name: "AIAV",
    sr: "653.11",
    cc: "2016/181",
    description: "Verordnung über den automatischen Informationsaustausch in Steuersachen"
  },
  {
    name: "StADG",
    sr: "651.4",
    cc: "2021/703",
    description: "Bundesgesetz über die Durchführung von internationalen Abkommen im Steuerbereich"
  },

  # --- Procedural / enforcement ---
  {
    name: "VStrR",
    sr: "313.0",
    cc: "1974/1857_1857_1857",
    description: "Bundesgesetz über das Verwaltungsstrafrecht"
  },
].freeze

# =============================================================================
# LOGGING
# =============================================================================

module Log
  def self.setup
    FileUtils.mkdir_p(OUTPUT_DIR)
    @logfile = File.open(LOG_FILE, 'a')
  end

  def self.write(level, message)
    line = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{level.upcase.ljust(5)}] #{message}"
    puts line
    @logfile&.puts(line)
    @logfile&.flush
  end

  def self.info(msg)  = write('info',  msg)
  def self.warn(msg)  = write('warn',  msg)
  def self.error(msg) = write('error', msg)
  def self.ok(msg)    = write('ok',    msg)
end

# =============================================================================
# STATE MANAGEMENT
# Persists which laws have been successfully downloaded.
# =============================================================================

module State
  def self.load
    if File.exist?(STATE_FILE)
      JSON.parse(File.read(STATE_FILE), symbolize_names: false)
    else
      { 'completed' => [], 'failed' => {}, 'started_at' => Time.now.iso8601 }
    end
  rescue JSON::ParserError
    Log.warn("State file corrupted, starting fresh.")
    { 'completed' => [], 'failed' => {}, 'started_at' => Time.now.iso8601 }
  end

  def self.save(state)
    File.write(STATE_FILE, JSON.pretty_generate(state))
  end

  def self.completed?(state, name)
    state['completed'].include?(name)
  end

  def self.mark_complete(state, name)
    state['completed'] << name unless state['completed'].include?(name)
    state['failed'].delete(name)
    save(state)
  end

  def self.mark_failed(state, name, reason)
    state['failed'][name] ||= []
    state['failed'][name] << { 'time' => Time.now.iso8601, 'reason' => reason }
    save(state)
  end
end

# =============================================================================
# HTTP
# =============================================================================

module HTTP
  def self.get(url, retries: MAX_RETRIES, accept: nil)
    uri = URI.parse(url)
    attempt = 0
    begin
      attempt += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'FedlexTaxScraper/1.0 (educational; contact: scraper@example.com)'
      req['Accept'] = accept || 'text/html,application/xhtml+xml,application/sparql-results+json'
      response = http.request(req)

      case response.code.to_i
      when 200
        response.body
      when 301, 302, 303, 307, 308
        new_url = response['Location']
        Log.info("  Redirect → #{new_url}")
        get(new_url, retries: retries - 1)
      when 429
        wait = (response['Retry-After'] || 30).to_i
        Log.warn("  Rate limited, waiting #{wait}s...")
        sleep(wait)
        raise "HTTP 429: rate limited (#{url})"
      else
        raise "HTTP #{response.code}: #{url}"
      end
    rescue => e
      if attempt < retries
        wait = attempt * 5
        Log.warn("  Attempt #{attempt} failed (#{e.message}), retrying in #{wait}s...")
        sleep(wait)
        retry
      else
        raise e
      end
    end
  end
end

# =============================================================================
# SPARQL: discover the current in-force HTML URL for a given Fedlex ELI URI
# =============================================================================

module Fedlex
  JOLUX = 'http://data.legilux.public.lu/resource/ontology/jolux#'

  # Returns the URL of the current German HTML manifestation for a given
  # work URI (e.g. https://fedlex.data.admin.ch/eli/cc/1991/1184_1184_1184)
  def self.current_html_url(work_uri)
    query = <<~SPARQL
      PREFIX jolux: <#{JOLUX}>

      SELECT ?url WHERE {
        ?expr jolux:language
          <http://publications.europa.eu/resource/authority/language/DEU> .
        ?expr jolux:isEmbodiedBy ?manif .
        ?manif jolux:userFormat
          <https://fedlex.data.admin.ch/vocabulary/user-format/html> .
        ?manif jolux:isExemplifiedBy ?url .
        FILTER(STRSTARTS(STR(?expr), "#{work_uri}/"))
      }
      ORDER BY DESC(?expr)
      LIMIT 1
    SPARQL

    encoded = CGI.escape(query.gsub(/\s+/, ' ').strip)
    sparql_url = "#{SPARQL_ENDPOINT}?query=#{encoded}"

    body = HTTP.get(sparql_url, accept: 'application/sparql-results+json')
    result = JSON.parse(body)
    bindings = result.dig('results', 'bindings') || []
    return nil if bindings.empty?

    bindings.first.dig('url', 'value')
  rescue => e
    Log.warn("  SPARQL lookup failed for #{work_uri}: #{e.message}")
    nil
  end

  # Fallback: also try the PDF URL for text extraction
  def self.current_pdf_url(work_uri)
    query = <<~SPARQL
      PREFIX jolux: <#{JOLUX}>

      SELECT ?url WHERE {
        ?expr jolux:language
          <http://publications.europa.eu/resource/authority/language/DEU> .
        ?expr jolux:isEmbodiedBy ?manif .
        ?manif jolux:userFormat
          <https://fedlex.data.admin.ch/vocabulary/user-format/pdf-a> .
        ?manif jolux:isExemplifiedBy ?url .
        FILTER(STRSTARTS(STR(?expr), "#{work_uri}/"))
      }
      ORDER BY DESC(?expr)
      LIMIT 1
    SPARQL

    encoded = CGI.escape(query.gsub(/\s+/, ' ').strip)
    sparql_url = "#{SPARQL_ENDPOINT}?query=#{encoded}"

    body = HTTP.get(sparql_url, accept: 'application/sparql-results+json')
    result = JSON.parse(body)
    bindings = result.dig('results', 'bindings') || []
    return nil if bindings.empty?

    bindings.first.dig('url', 'value')
  rescue => e
    nil
  end

  # Use SPARQL to discover all laws in the "Steuern" SR taxonomy (640–699)
  # that we might not have in KNOWN_LAWS
  def self.discover_tax_laws
    query = <<~SPARQL
      PREFIX jolux: <#{JOLUX}>

      SELECT DISTINCT ?work ?rsNumber ?titleDe WHERE {
        ?work jolux:historicalLegalId ?rsNumber .
        OPTIONAL {
          ?work jolux:isRealizedBy ?expr .
          ?expr jolux:language
            <http://publications.europa.eu/resource/authority/language/DEU> .
          ?expr jolux:titleShort ?titleDe .
        }
        FILTER(
          STRSTARTS(?rsNumber, "64")
          || STRSTARTS(?rsNumber, "65")
          || STRSTARTS(?rsNumber, "313.0")
          || STRSTARTS(?rsNumber, "68")
          || STRSTARTS(?rsNumber, "741.71")
        )
        FILTER(STRSTARTS(STR(?work), "https://fedlex.data.admin.ch/eli/cc/"))
      }
      ORDER BY ?rsNumber
    SPARQL

    encoded = CGI.escape(query.gsub(/\s+/, ' ').strip)
    sparql_url = "#{SPARQL_ENDPOINT}?query=#{encoded}"

    Log.info("Running SPARQL discovery query...")
    body = HTTP.get(sparql_url, accept: 'application/sparql-results+json')
    result = JSON.parse(body)
    (result.dig('results', 'bindings') || []).map do |b|
      {
        'work_uri' => b.dig('work', 'value'),
        'sr'       => b.dig('rsNumber', 'value'),
        'title'    => b.dig('titleDe', 'value') || '(no title)'
      }
    end
  rescue => e
    Log.warn("SPARQL discovery failed: #{e.message}")
    []
  end
end

# =============================================================================
# TEXT EXTRACTION from HTML
# =============================================================================

module TextExtractor
  def self.from_html(html_body)
    doc = Nokogiri::HTML(html_body)

    # Remove scripts, styles, navigation, headers/footers
    %w[script style nav header footer .navbar .breadcrumb .sidebar
       .menu .print-info [role="navigation"]].each do |selector|
      doc.css(selector).remove
    end

    # Fedlex HTML uses specific article containers; try to target the law body
    body_node = doc.at_css('article, .page-content, main, #content, body')
    return '' unless body_node

    # Extract text, preserving some structure
    lines = []
    body_node.traverse do |node|
      next unless node.text?
      text = node.text.strip
      next if text.empty?

      # Add spacing around block-level parents
      parent = node.parent
      tag = parent&.name&.downcase
      if %w[h1 h2 h3 h4 h5 h6].include?(tag)
        lines << "\n#{'=' * 60}"
        lines << text
        lines << '=' * 60
      elsif %w[p li dt dd td th].include?(tag)
        lines << text
      else
        lines << text
      end
    end

    lines.join("\n").squeeze("\n").strip
  end
end

# =============================================================================
# MAIN SCRAPER
# =============================================================================

class Scraper
  def initialize
    Log.setup
    FileUtils.mkdir_p(LAWS_DIR)
    @state = State.load
    Log.info("=" * 70)
    Log.info("Swiss Federal Tax Law Scraper starting up")
    Log.info("Already completed: #{@state['completed'].length} laws")
    Log.info("=" * 70)
  end

  def run
    # Step 1: Process known laws
    Log.info("\n--- PHASE 1: Processing #{KNOWN_LAWS.length} known tax laws ---\n")
    KNOWN_LAWS.each { |law| process_law(law) }

    # Step 2: SPARQL discovery for any additional laws
    Log.info("\n--- PHASE 2: SPARQL discovery for additional laws ---\n")
    sleep(REQUEST_DELAY)
    discovered = Fedlex.discover_tax_laws
    Log.info("SPARQL returned #{discovered.length} results")

    known_srs = KNOWN_LAWS.map { |l| l[:sr] }
    new_laws = discovered.reject { |d| known_srs.include?(d['sr']) }
    Log.info("Found #{new_laws.length} additional laws not in hardcoded list")

    new_laws.each do |d|
      # Extract CC path from the work URI
      # URI format: https://fedlex.data.admin.ch/eli/cc/{year}/{id}
      cc_match = d['work_uri']&.match(%r{/eli/cc/(.+)$})
      next unless cc_match

      law = {
        name:        "SR-#{d['sr']}",
        sr:          d['sr'],
        cc:          cc_match[1],
        description: d['title'],
        work_uri:    d['work_uri']
      }
      process_law(law)
    end

    # Step 3: Compile master file
    compile_master_file

    Log.info("\n" + "=" * 70)
    Log.info("Scraping complete.")
    Log.info("Completed: #{@state['completed'].length}")
    Log.info("Failed:    #{@state['failed'].length}")
    Log.info("Master file: #{MASTER_FILE}")
    Log.info("=" * 70)
  end

  private

  def process_law(law)
    name = law[:name] || law['name']
    sr   = law[:sr]   || law['sr']
    cc   = law[:cc]   || law['cc']
    desc = law[:description] || law['description'] || ''

    if State.completed?(@state, name)
      Log.info("SKIP  #{name} (#{sr}) — already done")
      return
    end

    Log.info("START #{name} (#{sr}) — #{desc}")

    work_uri = law[:work_uri] || "#{FEDLEX_BASE}/eli/cc/#{cc}"

    begin
      text = fetch_law_text(name, sr, work_uri)

      if text.nil? || text.strip.empty?
        raise "Empty text returned"
      end

      output_path = File.join(LAWS_DIR, "#{safe_filename(name)}.txt")
      header = build_header(name, sr, desc, work_uri)
      File.write(output_path, header + "\n\n" + text)

      State.mark_complete(@state, name)
      Log.ok("  DONE #{name} — #{text.length} chars → #{output_path}")

    rescue => e
      Log.error("  FAIL #{name}: #{e.message}")
      State.mark_failed(@state, name, e.message)
    end

    sleep(REQUEST_DELAY)
  end

  def fetch_law_text(name, sr, work_uri)
    # Try HTML first (cleanest for text extraction)
    Log.info("  Looking up HTML URL via SPARQL...")
    html_url = Fedlex.current_html_url(work_uri)
    sleep(REQUEST_DELAY)

    if html_url
      Log.info("  Fetching HTML: #{html_url}")
      html_body = HTTP.get(html_url)
      sleep(REQUEST_DELAY)
      text = TextExtractor.from_html(html_body)
      return text unless text.strip.empty?
      Log.warn("  HTML extracted empty text, trying PDF...")
    else
      Log.warn("  No HTML URL found via SPARQL, trying PDF...")
    end

    # Fallback: PDF
    pdf_url = Fedlex.current_pdf_url(work_uri)
    sleep(REQUEST_DELAY)

    if pdf_url
      Log.info("  Fetching PDF: #{pdf_url}")
      # Note: PDF text extraction requires pdf-reader gem.
      # If not available, save the raw PDF and note it.
      begin
        require 'pdf-reader'
        pdf_body = HTTP.get(pdf_url)
        tmp = Tempfile.new(['law', '.pdf'])
        tmp.binmode
        tmp.write(pdf_body)
        tmp.flush
        reader = PDF::Reader.new(tmp.path)
        text = reader.pages.map(&:text).join("\n")
        tmp.close
        tmp.unlink
        return text
      rescue LoadError
        Log.warn("  pdf-reader gem not available. Saving PDF URL instead.")
        return "[PDF available at: #{pdf_url}]\n[Install pdf-reader gem to extract text: gem install pdf-reader]"
      end
    end

    Log.warn("  No URL found for #{name}")
    nil
  end

  def compile_master_file
    Log.info("\n--- PHASE 3: Compiling master file ---")

    files = Dir.glob(File.join(LAWS_DIR, '*.txt')).sort
    Log.info("Compiling #{files.length} law files into #{MASTER_FILE}")

    File.open(MASTER_FILE, 'w') do |f|
      f.puts "=" * 80
      f.puts "SWISS FEDERAL TAX LAWS — FULL TEXT COMPILATION"
      f.puts "Scraped from fedlex.admin.ch"
      f.puts "Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      f.puts "Laws included: #{files.length}"
      f.puts "=" * 80
      f.puts ""

      # Table of contents
      f.puts "TABLE OF CONTENTS"
      f.puts "-" * 40
      files.each_with_index do |file, i|
        f.puts "#{(i + 1).to_s.rjust(3)}. #{File.basename(file, '.txt')}"
      end
      f.puts ""
      f.puts "=" * 80
      f.puts ""

      files.each do |file|
        content = File.read(file)
        f.puts content
        f.puts "\n\n" + "=" * 80 + "\n\n"
      end
    end

    size_mb = (File.size(MASTER_FILE) / 1024.0 / 1024.0).round(2)
    Log.ok("Master file written: #{MASTER_FILE} (#{size_mb} MB)")
  end

  def build_header(name, sr, desc, work_uri)
    [
      "=" * 80,
      "LAW: #{name}",
      "SR:  #{sr}",
      "TITLE: #{desc}",
      "SOURCE: #{work_uri}",
      "SCRAPED: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}",
      "=" * 80,
    ].join("\n")
  end

  def safe_filename(name)
    name.gsub(/[^a-zA-Z0-9\-_.]/, '_')
  end
end

# =============================================================================
# ENTRY POINT
# =============================================================================

# Handle Ctrl+C gracefully — progress is already saved after each law
trap('INT') do
  puts "\n\nInterrupted. Progress saved to #{STATE_FILE}. Re-run to continue."
  exit 0
end

Scraper.new.run
