#!/usr/bin/env ruby
# Formats law Markdown files into a unified clean format.
# Reads from output/laws/, writes to output/laws_formatted/

require 'fileutils'
require 'yaml'

INPUT_DIR  = File.join(__dir__, 'output', 'laws')
OUTPUT_DIR = File.join(__dir__, 'output', 'laws_formatted')

FileUtils.mkdir_p(OUTPUT_DIR)

# Common ligature/missing-space fixes from HTML-to-text conversion
SPACE_FIXES = [
  [/gesetz(ü)ber/i, 'gesetz über'],
  [/ordnung(ü)ber/i, 'ordnung über'],
  [/ordnung(z)um/i, 'ordnung zum'],
  [/ordnung(z)ur/i, 'ordnung zur'],
  [/vereinbarung(ü)ber/i, 'vereinbarung über'],
  [/abkommen(ü)ber/i, 'abkommen über'],
  [/beschluss(ü)ber/i, 'beschluss über'],
  [/erklärung(ü)ber/i, 'erklärung über'],
  [/vertrag(ü)ber/i, 'vertrag über'],
  [/protokoll(ü)ber/i, 'protokoll über'],
]

def fix_missing_spaces(text)
  SPACE_FIXES.each do |pattern, replacement|
    text = text.gsub(pattern) do |match|
      # Preserve original casing of first letter
      result = replacement.dup
      result[0] = match[0] if match[0] != match[0].downcase
      result
    end
  end
  text
end

def is_pdf_content?(body)
  lines = body.lines.reject { |l| l.strip.empty? }.take(15)
  has_heavy_indent = lines.count { |l| l.start_with?('    ') } > 3
  has_no_md_headings = !body.match?(/^\#{1,6}\s+\S/)
  has_heavy_indent || (has_no_md_headings && body.include?('Art.'))
end

def extract_title_from_body(body)
  if body =~ /^\# (.+)/
    $1.strip
  else
    # For PDF files: first substantial non-SR-number line
    body.lines.each do |line|
      stripped = line.strip
      next if stripped.empty?
      next if stripped.match?(/\A[\d.]+\z/)
      return stripped if stripped.length > 5
    end
    nil
  end
end

def clean_html_body(body)
  text = body.dup

  # Remove leading blank lines
  text.sub!(/\A\n+/, '')

  # Remove standalone SR number at the very top (e.g. "642.11\n")
  text.sub!(/\A[\d.]+\n+/, '')

  # Merge abbreviation line into title: "# Title\n\n## (ABBR)" → "# Title (ABBR)"
  text.gsub!(/^(\# .+)\n+^(\#\# \([A-Za-zÄÖÜäöü][\w, -]*\))/) do
    title = $1
    abbr = $2.sub(/\A\#\# /, '')
    "#{title} #{abbr}"
  end

  # Process line by line to remove footnotes and their references
  lines = text.lines
  result = []
  i = 0
  while i < lines.length
    line = lines[i]
    stripped = line.strip

    # --- Footnote block detection ---
    # Pattern 1: standalone number → SR/AS/BBl/amendment note
    if stripped.match?(/\A\d{1,3}\z/) && i + 1 < lines.length
      lookahead = lines[i + 1].strip
      if lookahead.match?(/\A(SR|AS|BBl)\z/) ||
         lookahead.match?(/\A\*\*[\d.]+/) ||
         lookahead.match?(/\A(Fassung gemäss|Eingefügt durch|Aufgehoben durch|Berichtigung|Bereinigt gemäss|Heute:|Bezeichnung gemäss|Ausdruck gemäss|BRB vom|Ursprünglich:|SR |AS |BBl |Mundartausdruck)/i)
        i = skip_footnote_block(lines, i + 1)
        next
      end
    end

    # Pattern 2: standalone SR/AS/BBl followed by bold number
    if stripped.match?(/\A(SR|AS|BBl)\z/) && i + 1 < lines.length && lines[i + 1].strip.match?(/\A\*\*[\d.]+/)
      i = skip_footnote_block(lines, i)
      next
    end

    # Pattern 3: Amendment note without preceding number (starts with "Fassung gemäss" etc.)
    if stripped.match?(/\A(Fassung gemäss|Eingefügt durch|Aufgehoben durch|Berichtigung|Bereinigt gemäss|Bezeichnung gemäss|Ausdruck gemäss|BRB vom|Ursprünglich:)/i) &&
       (stripped.include?('AS') || stripped.include?('BBl') || stripped.include?('Kraft seit') ||
        (i + 1 < lines.length && lines[i + 1].strip.match?(/\A(\*\*|AS\b|BBl\b|SR\b|\()/)))
      i = skip_footnote_block(lines, i)
      next
    end

    # --- Superscript footnote reference detection ---
    # Standalone number that is a footnote ref (not a paragraph number)
    # Paragraph numbers: "1\n Der Bund..." (number + space-indented text)
    # Footnote refs: "1\n," or "1\n\n" or "1\nCapitalized..." (after removing footnote blocks)
    if stripped.match?(/\A\d{1,3}\z/) && i + 1 < lines.length
      next_line = lines[i + 1]
      # Keep if it's a paragraph number: next line starts with space+text
      if next_line.match?(/\A [A-ZÄÖÜa-zäöü]/)
        result << line
        i += 1
        next
      end
      # Skip footnote reference
      i += 1
      next
    end

    # Skip standalone bold numbers (remnant footnote artifacts)
    if stripped.match?(/\A\*\*[\d.]+\*\*\z/)
      i += 1
      next
    end

    # Skip orphaned SR/AS/BBl lines
    if stripped.match?(/\A(SR|AS|BBl)\z/)
      i += 1
      next
    end

    # Skip lines that are just year numbers (remnants of AS **2019** blocks)
    if stripped.match?(/\A\d{4}\z/)
      i += 1
      next
    end

    # Skip orphaned punctuation lines from removed footnote refs
    if stripped.match?(/\A[,;.)]+\z/)
      i += 1
      next
    end

    result << line
    i += 1
  end
  result.join
end

def skip_footnote_block(lines, start_i)
  i = start_i
  while i < lines.length
    s = lines[i].strip
    # Stop at empty line not followed by more footnote content
    if s.empty?
      if i + 1 < lines.length
        next_s = lines[i + 1].strip
        break unless next_s.match?(/\A(\*\*|AS\b|BBl\b|SR\b|\d{4}\b|\)\.?|;\n?|\d{1,3}\z)/)
      else
        break
      end
    end
    # Stop at markdown headings
    break if s.match?(/\A\#{1,6}\s/)
    break if s.match?(/\A#{5}\s/)
    # Stop at article content (letter + period list items, paragraph numbers with text)
    break if s.match?(/\A[a-z]\.\z/) # list items
    i += 1
  end
  i
end

def clean_pdf_body(body)
  lines = body.lines.map(&:rstrip)

  # Remove page headers/footers
  lines.reject! do |line|
    stripped = line.strip
    stripped.match?(/\A\d[\d.]+\s{10,}(Steuern|Impôts|Imposte)/) ||
      stripped.match?(/\A\s{20,}\d[\d.]+\z/) ||
      stripped.match?(/\A\s{20,}\d{1,3}\z/)
  end

  # Strip leading whitespace uniformly
  non_empty = lines.select { |l| !l.strip.empty? }
  min_indent = non_empty.map { |l| l[/\A */].length }.min || 0
  lines.map! { |l| l.strip.empty? ? '' : (l[min_indent..] || '') }

  # Remove standalone SR number at top
  while lines.first&.strip&.empty?
    lines.shift
  end
  if lines.first&.strip&.match?(/\A[\d.]+\z/)
    lines.shift
  end

  # Convert "Art. N  Title" to markdown heading
  lines.map! do |line|
    if line.match?(/\AArt\.\s+\d+/)
      "\n##### " + line.strip.gsub(/\s{2,}/, ' ')
    else
      line
    end
  end

  # Try to make the first substantial line a heading if it isn't already
  first_text_idx = lines.index { |l| !l.strip.empty? }
  if first_text_idx && !lines[first_text_idx].start_with?('#')
    # Collect multi-line title: all lines until blank line followed by "vom DD..."
    title_lines = []
    idx = first_text_idx
    while idx < lines.length
      stripped = lines[idx].strip
      # Stop at "vom DD. Month YYYY" (date line)
      break if stripped.match?(/\Avom \d/)
      # Stop at double blank line
      if stripped.empty?
        # Check if this is just a single blank between title parts
        if idx + 1 < lines.length && !lines[idx + 1].strip.empty? &&
           !lines[idx + 1].strip.match?(/\Avom \d/) &&
           !lines[idx + 1].strip.match?(/\A(Der|Die|Das|Gestützt|Im Einvernehmen)/i)
          title_lines << stripped
          idx += 1
          next
        end
        break
      end
      title_lines << stripped
      idx += 1
    end
    if title_lines.any?
      full_title = title_lines.reject(&:empty?).join(' ').gsub(/\s{2,}/, ' ')
      lines[first_text_idx...idx] = ["# #{full_title}"]
    end
  end

  # Remove PDF footer references (e.g. "AS 2007 1799\n1    SR 641.20")
  text = lines.join("\n")
  text.gsub!(/\nAS \d{4} \d+\n(?:\d+\s+SR [\d.]+\n?)*/, "\n")
  text.gsub!(/\n\d+\s+SR [\d.]+/, '')
  text.gsub!(/\n\d+\s+\[AS \d{4} \d+\]/, '')

  # Remove trailing page numbers and right-aligned numbers
  text.gsub!(/\n\s{10,}\d{1,3}\s*$/, '')
  # Remove standalone trailing numbers at end
  text.gsub!(/\n\d{1,2}\s*\z/, '')

  text
end

def collapse_blank_lines(text)
  text.gsub(/\n{3,}/, "\n\n")
end

Dir.glob(File.join(INPUT_DIR, '*.md')).sort.each do |path|
  content = File.read(path, encoding: 'utf-8')
  filename = File.basename(path)

  # Split front matter and body
  if content.match?(/\A---\n/)
    parts = content.split(/^---\n/, 3)
    front_matter = YAML.safe_load(parts[1], permitted_classes: [Time, Date])
    body = parts[2] || ''
  else
    front_matter = {}
    body = content
  end

  # Fix missing spaces
  body = fix_missing_spaces(body)

  # Process based on source type
  if is_pdf_content?(body)
    body = clean_pdf_body(body)
  else
    body = clean_html_body(body)
  end

  # Fix title in front matter
  if front_matter['title'] == '(no title)' || front_matter['title'].nil?
    extracted = extract_title_from_body(body)
    front_matter['title'] = fix_missing_spaces(extracted) if extracted
  elsif front_matter['title']
    front_matter['title'] = fix_missing_spaces(front_matter['title'])
  end

  # Collapse blank lines and trim
  body = collapse_blank_lines(body).strip + "\n"

  # Rebuild with clean YAML front matter
  # Quote title to avoid YAML issues
  title = front_matter['title']&.gsub('"', '\\"') || '(no title)'
  output = <<~YAML
    ---
    law: #{front_matter['law']}
    sr: #{front_matter['sr']}
    title: "#{title}"
    source: #{front_matter['source']}
    scraped: "#{front_matter['scraped']}"
    ---

  YAML
  output += body

  File.write(File.join(OUTPUT_DIR, filename), output, encoding: 'utf-8')
  puts "Formatted: #{filename}"
end

puts "\nDone. #{Dir.glob(File.join(OUTPUT_DIR, '*.md')).count} files written to #{OUTPUT_DIR}"
