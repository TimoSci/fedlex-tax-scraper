# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'TextExtractor' do
  let(:tmp_dir) { Dir.mktmpdir }

  before(:each) do
    unload_scraper_constants!
    load_scraper_code(tmp_dir)
  end

  after(:each) do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.from_html' do
    it 'extracts text from a simple HTML body' do
      html = <<~HTML
        <html>
        <body>
          <article>
            <p>Artikel 1: Gegenstand</p>
            <p>Dieses Gesetz regelt die Erhebung der Bundessteuer.</p>
          </article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Artikel 1: Gegenstand')
      expect(text).to include('Dieses Gesetz regelt die Erhebung der Bundessteuer.')
    end

    it 'removes script and style tags' do
      html = <<~HTML
        <html>
        <body>
          <script>var x = 1;</script>
          <style>.hidden { display: none; }</style>
          <article><p>Visible content</p></article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Visible content')
      expect(text).not_to include('var x = 1')
      expect(text).not_to include('display: none')
    end

    it 'removes navigation elements' do
      html = <<~HTML
        <html>
        <body>
          <nav>Navigation links</nav>
          <header>Site header</header>
          <footer>Site footer</footer>
          <article><p>Law text</p></article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Law text')
      expect(text).not_to include('Navigation links')
      expect(text).not_to include('Site header')
      expect(text).not_to include('Site footer')
    end

    it 'formats headings with separator lines' do
      html = <<~HTML
        <html>
        <body>
          <article>
            <h1>Erster Titel</h1>
            <p>Inhalt</p>
          </article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('=' * 60)
      expect(text).to include('Erster Titel')
    end

    it 'returns empty string when no body node is found' do
      html = ''
      text = TextExtractor.from_html(html)
      expect(text).to be_a(String)
    end

    it 'handles a realistic Fedlex-like HTML structure' do
      html = <<~HTML
        <html>
        <head><title>SR 642.11</title></head>
        <body>
          <div class="navbar">Menu</div>
          <div class="breadcrumb">Home > Laws</div>
          <main>
            <h1>Bundesgesetz über die direkte Bundessteuer</h1>
            <h2>1. Titel: Allgemeine Bestimmungen</h2>
            <p>Art. 1 Gegenstand des Gesetzes</p>
            <p>Der Bund erhebt als direkte Bundessteuer:</p>
            <li>eine Einkommenssteuer von den natürlichen Personen;</li>
            <li>eine Gewinnsteuer von den juristischen Personen.</li>
            <h2>2. Titel: Einkommenssteuer</h2>
            <p>Art. 16 Steuerbares Einkommen</p>
            <p>Der Einkommenssteuer unterliegen alle wiederkehrenden und einmaligen Einkünfte.</p>
          </main>
          <div class="sidebar">Related laws</div>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Bundesgesetz über die direkte Bundessteuer')
      expect(text).to include('Art. 1 Gegenstand des Gesetzes')
      expect(text).to include('Einkommenssteuer')
      expect(text).not_to include('Menu')
      expect(text).not_to include('Home > Laws')
      expect(text).not_to include('Related laws')
    end

    it 'removes elements with role="navigation"' do
      html = <<~HTML
        <html>
        <body>
          <div role="navigation">Nav bar</div>
          <article><p>Content</p></article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Content')
      expect(text).not_to include('Nav bar')
    end

    it 'removes .print-info and .menu classes' do
      html = <<~HTML
        <html>
        <body>
          <div class="print-info">Print version</div>
          <div class="menu">Menu items</div>
          <article><p>Law text</p></article>
        </body>
        </html>
      HTML

      text = TextExtractor.from_html(html)
      expect(text).to include('Law text')
      expect(text).not_to include('Print version')
      expect(text).not_to include('Menu items')
    end
  end
end
