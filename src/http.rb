
# Simple HTTP GET with redirect following, retries, and rate-limit handling.

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
