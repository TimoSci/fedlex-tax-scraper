# Main orchestrator: processes known laws, discovers new ones, and compiles output.
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

      output_path = File.join(LAWS_DIR, "#{safe_filename(name)}.md")
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
    result = try_fetch_law(name, work_uri)
    return result if result

    # The hardcoded CC path may be wrong — resolve work URIs from the SR number
    Log.info("  Resolving work URI from SR number #{sr}...")
    candidates = Fedlex.work_uris_for_sr(sr)
    sleep(REQUEST_DELAY)

    candidates.each do |uri|
      next if uri == work_uri

      Log.info("  Trying work URI: #{uri}")
      result = try_fetch_law(name, uri)
      return result if result
    end

    Log.warn("  No URL found for #{name}")
    nil
  end

  def try_fetch_law(name, work_uri)
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

    pdf_url = Fedlex.current_pdf_url(work_uri)
    sleep(REQUEST_DELAY)

    if pdf_url
      Log.info("  Fetching PDF: #{pdf_url}")
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
      rescue => e
        Log.warn("  PDF parsing failed: #{e.message}")
        return nil
      end
    end

    nil
  end

  def compile_master_file
    Log.info("\n--- PHASE 3: Compiling master file ---")

    files = Dir.glob(File.join(LAWS_DIR, '*.md')).sort
    Log.info("Compiling #{files.length} law files into #{MASTER_FILE}")

    File.open(MASTER_FILE, 'w') do |f|
      f.puts "# SWISS FEDERAL TAX LAWS"
      f.puts ""
      f.puts "Full text compilation scraped from fedlex.admin.ch"
      f.puts ""
      f.puts "- **Generated:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      f.puts "- **Laws included:** #{files.length}"
      f.puts ""
      f.puts "---"
      f.puts ""

      # Table of contents
      f.puts "## TABLE OF CONTENTS"
      f.puts ""
      files.each_with_index do |file, i|
        f.puts "#{i + 1}. #{File.basename(file, '.md')}"
      end
      f.puts ""
      f.puts "---"
      f.puts ""

      files.each do |file|
        content = File.read(file)
        f.puts content
        f.puts ""
        f.puts "---"
        f.puts ""
      end
    end

    size_mb = (File.size(MASTER_FILE) / 1024.0 / 1024.0).round(2)
    Log.ok("Master file written: #{MASTER_FILE} (#{size_mb} MB)")
  end

  def build_header(name, sr, desc, work_uri)
    [
      "---",
      "law: #{name}",
      "sr: #{sr}",
      "title: #{desc}",
      "source: #{work_uri}",
      "scraped: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}",
      "---",
    ].join("\n")
  end

  def safe_filename(name)
    name.gsub(/[^a-zA-Z0-9\-_.]/, '_')
  end
end
