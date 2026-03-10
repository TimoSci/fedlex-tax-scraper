
# SPARQL queries against the fedlex linked-data endpoint to resolve law URLs.

module Fedlex
  JOLUX = 'http://data.legilux.public.lu/resource/ontology/jolux#'

  # Look up all candidate work URIs for a given SR number.
  # Returns an array of distinct work URIs (newest first), or empty array.
  def self.work_uris_for_sr(sr_number)
    query = <<~SPARQL
      PREFIX jolux: <#{JOLUX}>

      SELECT DISTINCT ?work WHERE {
        ?work a jolux:ConsolidationAbstract .
        ?work jolux:historicalLegalId '#{sr_number}' .
        FILTER(STRSTARTS(STR(?work), "https://fedlex.data.admin.ch/eli/cc/"))
      }
      ORDER BY DESC(?work)
    SPARQL

    encoded = CGI.escape(query.gsub(/\s+/, ' ').strip)
    sparql_url = "#{SPARQL_ENDPOINT}?query=#{encoded}"

    body = HTTP.get(sparql_url, accept: 'application/sparql-results+json')
    result = JSON.parse(body)
    bindings = result.dig('results', 'bindings') || []

    bindings.map { |b| b.dig('work', 'value') }.uniq
  rescue => e
    Log.warn("  SPARQL work URI lookup failed for SR #{sr_number}: #{e.message}")
    []
  end

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
        ?work a jolux:ConsolidationAbstract .
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
      ORDER BY ?rsNumber DESC(?work)
    SPARQL

    encoded = CGI.escape(query.gsub(/\s+/, ' ').strip)
    sparql_url = "#{SPARQL_ENDPOINT}?query=#{encoded}"

    Log.info("Running SPARQL discovery query...")
    body = HTTP.get(sparql_url, accept: 'application/sparql-results+json')
    result = JSON.parse(body)
    seen = {}
    (result.dig('results', 'bindings') || []).each do |b|
      sr = b.dig('rsNumber', 'value')
      next if seen.key?(sr)

      seen[sr] = {
        'work_uri' => b.dig('work', 'value'),
        'sr'       => sr,
        'title'    => b.dig('titleDe', 'value') || '(no title)'
      }
    end
    seen.values
  rescue => e
    Log.warn("SPARQL discovery failed: #{e.message}")
    []
  end
end
