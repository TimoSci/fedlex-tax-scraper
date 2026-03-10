#!/usr/bin/env ruby
# Formats raw scraped law files into a unified clean format.

require_relative 'src/config'
require_relative 'src/law_formatter'

count = LawFormatter.format_all(LAWS_DIR, LAWS_FORMATTED_DIR)
puts "Done. #{count} files written to #{LAWS_FORMATTED_DIR}"
