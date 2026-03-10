# frozen_string_literal: true

require 'webmock/rspec'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'nokogiri'

# Disable all real HTTP connections in tests
WebMock.disable_net_connect!

# Build a single source string from all the split source files.
# Order matters: config and known_laws first, then modules, then Scraper class.
SRC_DIR = File.expand_path('../../src', __FILE__)
SCRAPER_SOURCE = [
  'config.rb',
  'known_laws.rb',
  'log.rb',
  'state.rb',
  'http.rb',
  'fedlex.rb',
  'text_extractor.rb',
  'scraper.rb',
].map { |f| File.read(File.join(SRC_DIR, f)) }.join("\n")

# Writes a modified copy of the scraper source to a temp file and loads it.
# This avoids eval issues with retry/rescue in Ruby 4.0+ while still
# allowing us to redirect output paths and disable delays for tests.
def load_scraper_code(tmp_output_dir)
  modified = SCRAPER_SOURCE.dup

  # Override OUTPUT_DIR and related constants
  modified.sub!(/^OUTPUT_DIR\s*=.*$/, "OUTPUT_DIR = '#{tmp_output_dir}'")
  modified.sub!(/^LAWS_DIR\s*=.*$/, "LAWS_DIR = File.join(OUTPUT_DIR, 'laws')")
  modified.sub!(/^LOG_FILE\s*=.*$/, "LOG_FILE = File.join(OUTPUT_DIR, 'scraper.log')")
  modified.sub!(/^STATE_FILE\s*=.*$/, "STATE_FILE = File.join(OUTPUT_DIR, 'state.json')")
  modified.sub!(/^MASTER_FILE\s*=.*$/, "MASTER_FILE = File.join(OUTPUT_DIR, 'swiss_federal_tax_laws_FULLTEXT.md')")

  # Reduce delays for fast tests
  modified.sub!(/^REQUEST_DELAY\s*=.*$/, 'REQUEST_DELAY = 0')
  modified.sub!(/^HTTP_TIMEOUT\s*=.*$/, 'HTTP_TIMEOUT = 5')

  # Write to a temp file and load it (avoids eval issues with retry/rescue)
  tmpfile = File.join(tmp_output_dir, '_scraper_test.rb')
  FileUtils.mkdir_p(tmp_output_dir)
  File.write(tmpfile, modified)
  load(tmpfile)
end

# Helper to clean up constants/modules between tests so each spec
# gets a fresh set of definitions pointing at its own temp directory.
def unload_scraper_constants!
  %w[OUTPUT_DIR LAWS_DIR LOG_FILE STATE_FILE MASTER_FILE
     REQUEST_DELAY HTTP_TIMEOUT MAX_RETRIES SPARQL_ENDPOINT
     FEDLEX_BASE KNOWN_LAWS].each do |c|
    Object.send(:remove_const, c) if Object.const_defined?(c)
  end
  %w[Log State HTTP Fedlex TextExtractor].each do |m|
    Object.send(:remove_const, m) if Object.const_defined?(m)
  end
  Object.send(:remove_const, :Scraper) if Object.const_defined?(:Scraper)
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  config.filter_run_when_matching :focus
end
