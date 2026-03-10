#!/usr/bin/env ruby
# =============================================================================
# fedlex_tax_scraper.rb
#
# Scrapes the full text of all Swiss federal tax laws from fedlex.admin.ch.
# Restartable: tracks progress in a JSON state file and skips already-fetched laws.
# Outputs one .md file per law, then compiles everything into a single master file.
#
# USAGE:
#   gem install nokogiri          # for HTML parsing
#   ruby fedlex_tax_scraper.rb
#
# OUTPUT:
#   ./output/laws/        — one .md file per law
#   ./output/scraper.log  — full timestamped log
#   ./output/state.json   — progress tracker (restart-safe)
#   ./output/swiss_federal_tax_laws_FULLTEXT.md  — compiled master file
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

require_relative 'config'
require_relative 'known_laws'
require_relative 'log'
require_relative 'state'
require_relative 'http'
require_relative 'fedlex'
require_relative 'text_extractor'
require_relative 'scraper'

# =============================================================================
# ENTRY POINT
# =============================================================================

# Handle Ctrl+C gracefully — progress is already saved after each law
trap('INT') do
  puts "\n\nInterrupted. Progress saved to #{STATE_FILE}. Re-run to continue."
  exit 0
end

Scraper.new.run
