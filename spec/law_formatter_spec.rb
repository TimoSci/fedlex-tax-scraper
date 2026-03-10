# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../src/law_formatter'

RSpec.describe LawFormatter do
  describe '.fix_missing_spaces' do
    it 'fixes "gesetzüber" ligature' do
      expect(LawFormatter.fix_missing_spaces('Bundesgesetzüber die Steuer')).to eq('Bundesgesetz über die Steuer')
    end

    it 'fixes "ordnungüber" ligature' do
      expect(LawFormatter.fix_missing_spaces('Verordnungüber den Vollzug')).to eq('Verordnung über den Vollzug')
    end

    it 'preserves capitalization of first character' do
      expect(LawFormatter.fix_missing_spaces('Gesetzüber')).to eq('Gesetz über')
      expect(LawFormatter.fix_missing_spaces('gesetzüber')).to eq('gesetz über')
    end

    it 'fixes multiple ligatures in the same text' do
      text = 'Bundesgesetzüber die Verordnungüber Steuern'
      result = LawFormatter.fix_missing_spaces(text)
      expect(result).to eq('Bundesgesetz über die Verordnung über Steuern')
    end

    it 'leaves text without ligatures unchanged' do
      text = 'Bundesgesetz über die direkte Bundessteuer'
      expect(LawFormatter.fix_missing_spaces(text)).to eq(text)
    end
  end

  describe '.pdf_content?' do
    it 'detects PDF content with heavy indentation' do
      body = (1..10).map { "    indented line\n" }.join
      expect(LawFormatter.pdf_content?(body)).to be true
    end

    it 'detects PDF content without markdown headings but with Art.' do
      body = "Some preamble\nArt. 1 Gegenstand\nDer Bund erhebt...\n"
      expect(LawFormatter.pdf_content?(body)).to be true
    end

    it 'returns false for markdown content with headings' do
      body = "# Title\n\n##### Art. 1 Test\n\nSome content\n"
      expect(LawFormatter.pdf_content?(body)).to be false
    end
  end

  describe '.extract_title_from_body' do
    it 'extracts title from markdown heading' do
      body = "# Bundesgesetz über die Steuer\n\nvom 1. Januar 2020\n"
      expect(LawFormatter.extract_title_from_body(body)).to eq('Bundesgesetz über die Steuer')
    end

    it 'extracts title from plain text (PDF) body' do
      body = "\n641.20\nVerordnung des EFD über Steuern\nvom 1. Januar 2020\n"
      expect(LawFormatter.extract_title_from_body(body)).to eq('Verordnung des EFD über Steuern')
    end

    it 'skips SR numbers when extracting from plain text' do
      body = "642.11\nBundesgesetz über die direkte Bundessteuer\n"
      expect(LawFormatter.extract_title_from_body(body)).to eq('Bundesgesetz über die direkte Bundessteuer')
    end

    it 'returns nil for empty body' do
      expect(LawFormatter.extract_title_from_body('')).to be_nil
    end
  end

  describe '.clean_html_body' do
    it 'removes standalone SR number at the top' do
      body = "\n642.11\n\n# Title\n\nContent\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).to start_with('# Title')
      expect(result).not_to include('642.11')
    end

    it 'merges abbreviation subtitle into title' do
      body = "# Bundesgesetz über die direkte Bundessteuer\n\n## (DBG)\n\nvom 14. Dezember 1990\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).to include('# Bundesgesetz über die direkte Bundessteuer (DBG)')
      expect(result).not_to match(/^## \(DBG\)/)
    end

    it 'removes footnote reference numbers' do
      body = "# Title\n\ngestützt auf Artikel 128\n1\n,\n2\n\nbeschliesst:\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).to include('gestützt auf Artikel 128')
      expect(result).not_to match(/^1$/)
    end

    it 'removes footnote blocks (number + SR/AS/BBl)' do
      body = <<~MD
        # Title

        beschliesst:

        1
        SR
        **101**

        # Erster Teil
      MD
      result = LawFormatter.clean_html_body(body)
      expect(result).not_to include('**101**')
      expect(result).not_to include('SR')
      expect(result).to include('# Erster Teil')
    end

    it 'removes amendment notes (Fassung gemäss)' do
      body = <<~MD
        # Title

        ##### Art. 1 Test

        Content here.

        Fassung gemäss Ziff. I des BG vom 16. Juni 2023, in Kraft seit 1. Jan. 2025

        ##### Art. 2 Next
      MD
      result = LawFormatter.clean_html_body(body)
      expect(result).not_to include('Fassung gemäss')
      expect(result).to include('##### Art. 1 Test')
      expect(result).to include('##### Art. 2 Next')
    end

    it 'keeps paragraph numbers (number followed by space-indented text)' do
      body = "# Title\n\n1\n Der Bund erhebt eine Steuer.\n\n2\n Als Steuer erhebt er:\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).to include("1\n Der Bund erhebt")
      expect(result).to include("2\n Als Steuer erhebt")
    end

    it 'removes orphaned bold numbers' do
      body = "# Title\n\n**2019**\n\nContent\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).not_to include('**2019**')
      expect(result).to include('Content')
    end

    it 'removes orphaned year numbers' do
      body = "# Title\n\n2019\n\nContent\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).not_to match(/^2019$/)
      expect(result).to include('Content')
    end

    it 'removes orphaned punctuation lines' do
      body = "# Title\n\n,\n\n.\n\n)\n\nContent\n"
      result = LawFormatter.clean_html_body(body)
      expect(result).not_to match(/^,$/)
      expect(result).not_to match(/^\.$/)
      expect(result).to include('Content')
    end
  end

  describe '.skip_footnote_block' do
    it 'skips past SR bold number block' do
      lines = ["SR\n", "**101**\n", "\n", "# Next heading\n"]
      result = LawFormatter.skip_footnote_block(lines, 0)
      expect(result).to eq(2) # stops at the blank line before heading
    end

    it 'stops at markdown heading' do
      lines = ["SR\n", "**101**\n", "# Heading\n"]
      result = LawFormatter.skip_footnote_block(lines, 0)
      expect(result).to eq(2)
    end

    it 'continues past blank lines followed by more footnote content' do
      lines = ["AS\n", "**2019**\n", "\n", "**2413**\n", "\n", "# Heading\n"]
      result = LawFormatter.skip_footnote_block(lines, 0)
      expect(result).to eq(4) # stops at second blank line
    end
  end

  describe '.clean_pdf_body' do
    it 'removes page headers with SR number and Steuern' do
      body = "    Content line\n641.20                          Steuern\n    More content\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).not_to include('Steuern')
      expect(result).to include('Content line')
    end

    it 'removes standalone SR number at top' do
      body = "641.201.41\nVerordnung des EFD\nüber die Steuerbefreiung\n\nvom 4. April 2007\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).not_to match(/\A641/)
    end

    it 'converts Art. lines to markdown headings' do
      body = "Title text\n\nvom 1. Januar 2020\n\nArt. 1  Gegenstand\nDer Bund erhebt.\n\nArt. 2  Begriffe\nErdöl.\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).to include('##### Art. 1 Gegenstand')
      expect(result).to include('##### Art. 2 Begriffe')
    end

    it 'creates heading from multi-line title' do
      body = "Verordnung des EFD\nüber die Steuerbefreiung\nvon Gegenständen\n\nvom 4. April 2007\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).to include('# Verordnung des EFD über die Steuerbefreiung von Gegenständen')
    end

    it 'removes PDF footer references' do
      body = "Verordnung über Steuern\n\nvom 1. Januar 2020\n\nDer Bundesrat verordnet:\n\nArt. 1  Gegenstand\nInhalt.\nAS 2007 1799\n1    SR 641.20\n\nArt. 2  Schluss\nEnde.\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).not_to include('AS 2007 1799')
      expect(result).not_to include('SR 641.20')
      expect(result).to include('##### Art. 1 Gegenstand')
    end

    it 'removes trailing right-aligned page numbers' do
      body = "Content line\n                                                     1\n"
      result = LawFormatter.clean_pdf_body(body)
      expect(result).to include('Content line')
      expect(result).not_to match(/\s{10,}\d\s*$/)
    end
  end

  describe '.collapse_blank_lines' do
    it 'collapses three or more blank lines to two' do
      text = "Line 1\n\n\n\nLine 2\n"
      expect(LawFormatter.collapse_blank_lines(text)).to eq("Line 1\n\nLine 2\n")
    end

    it 'preserves single blank lines' do
      text = "Line 1\n\nLine 2\n"
      expect(LawFormatter.collapse_blank_lines(text)).to eq(text)
    end
  end

  describe '.parse_file' do
    it 'parses YAML front matter and body' do
      content = "---\nlaw: DBG\nsr: 642.11\ntitle: Test\n---\n\n# Body\n"
      front_matter, body = LawFormatter.parse_file(content)
      expect(front_matter['law']).to eq('DBG')
      expect(front_matter['sr']).to eq(642.11)
      expect(body).to include('# Body')
    end

    it 'handles content without front matter' do
      content = "# Just a heading\n\nSome text\n"
      front_matter, body = LawFormatter.parse_file(content)
      expect(front_matter).to eq({})
      expect(body).to eq(content)
    end

    it 'handles Time values in front matter' do
      content = "---\nscraped: 2026-03-10 00:40:05 +0100\n---\n\nBody\n"
      front_matter, _body = LawFormatter.parse_file(content)
      expect(front_matter['scraped']).to be_a(Time)
    end
  end

  describe '.format_law' do
    it 'produces clean output for an HTML-extracted law' do
      content = <<~MD
        ---
        law: DBG
        sr: 642.11
        title: Bundesgesetz über die direkte Bundessteuer
        source: https://example.com
        scraped: 2026-03-10 00:40:05
        ---

        642.11

        # Bundesgesetz über die direkte Bundessteuer

        ## (DBG)

        vom 14. Dezember 1990

        beschliesst:

        1
        SR
        **101**

        # Erster Teil
      MD

      result = LawFormatter.format_law(content)
      expect(result).to include('title: "Bundesgesetz über die direkte Bundessteuer"')
      expect(result).to include('# Bundesgesetz über die direkte Bundessteuer (DBG)')
      expect(result).not_to include('**101**')
      expect(result).to include('# Erster Teil')
    end

    it 'fixes (no title) in front matter' do
      content = <<~MD
        ---
        law: SR-641.131
        sr: 641.131
        title: "(no title)"
        source: https://example.com
        scraped: 2026-03-10 00:56:09
        ---

        641.131

        # Verordnung über die Aufhebung der Umsatzabgabe

        vom 15. März 1993
      MD

      result = LawFormatter.format_law(content)
      expect(result).to include('title: "Verordnung über die Aufhebung der Umsatzabgabe"')
      expect(result).not_to include('(no title)')
    end

    it 'fixes ligatures in title front matter' do
      content = <<~MD
        ---
        law: TEST
        sr: 641.00
        title: Bundesgesetzüber die Steuer
        source: https://example.com
        scraped: 2026-03-10 00:00:00
        ---

        # Bundesgesetzüber die Steuer
      MD

      result = LawFormatter.format_law(content)
      expect(result).to include('title: "Bundesgesetz über die Steuer"')
      expect(result).to include('# Bundesgesetz über die Steuer')
    end
  end

  describe '.format_all' do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:input_dir) { File.join(tmp_dir, 'input') }
    let(:output_dir) { File.join(tmp_dir, 'output') }

    before { FileUtils.mkdir_p(input_dir) }
    after { FileUtils.rm_rf(tmp_dir) }

    it 'formats all files from input to output directory' do
      File.write(File.join(input_dir, 'test1.md'), <<~MD)
        ---
        law: T1
        sr: 1.0
        title: Test One
        source: https://example.com
        scraped: 2026-01-01 00:00:00
        ---

        # Test One

        Content.
      MD

      File.write(File.join(input_dir, 'test2.md'), <<~MD)
        ---
        law: T2
        sr: 2.0
        title: Test Two
        source: https://example.com
        scraped: 2026-01-01 00:00:00
        ---

        # Test Two

        Content.
      MD

      count = LawFormatter.format_all(input_dir, output_dir)
      expect(count).to eq(2)
      expect(File.exist?(File.join(output_dir, 'test1.md'))).to be true
      expect(File.exist?(File.join(output_dir, 'test2.md'))).to be true

      result = File.read(File.join(output_dir, 'test1.md'))
      expect(result).to include('title: "Test One"')
    end

    it 'creates output directory if it does not exist' do
      File.write(File.join(input_dir, 'test.md'), <<~MD)
        ---
        law: T
        sr: 1.0
        title: Test
        source: https://example.com
        scraped: 2026-01-01 00:00:00
        ---

        # Test
      MD

      nested_output = File.join(output_dir, 'nested', 'deep')
      LawFormatter.format_all(input_dir, nested_output)
      expect(Dir.exist?(nested_output)).to be true
    end

    it 'returns 0 for empty input directory' do
      count = LawFormatter.format_all(input_dir, output_dir)
      expect(count).to eq(0)
    end
  end
end
