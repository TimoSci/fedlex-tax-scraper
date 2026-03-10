# Fedlex Tax Scraper

Scrapes the full text of Swiss federal tax laws from [fedlex.admin.ch](https://www.fedlex.admin.ch) and saves them as Markdown files.

The scraper uses SPARQL queries against the Fedlex linked-data endpoint to discover law texts, fetches them as HTML, and converts them to clean Markdown. It is restartable — progress is tracked in a JSON state file, so interrupted runs can be resumed.

## What it covers

- Direct federal taxes (DBG, StHG, and related ordinances)
- VAT (MWSTG, MWSTV)
- Withholding tax (VStG, VStV)
- Stamp duties (StG, StV)
- Minimum tax / OECD Pillar Two (EStG, MindStV)
- Special consumption taxes (beer, tobacco, mineral oil, spirits, CO2, heavy vehicle charges)
- International tax assistance (StAhiG, AIAG, StADG)
- Administrative criminal law (VStrR)

Beyond the hardcoded list, the scraper also runs a SPARQL discovery query to find additional tax laws in the SR 640–699 range.

## Installation

Requires Ruby (tested with 4.x).

```sh
bundle install
```

Or run the script:

```sh
./install.sh
```


Or install gems manually:

```sh
gem install nokogiri pdf-reader
```

`pdf-reader` is optional — it enables text extraction from PDF when no HTML version is available.

## Usage

```sh
ruby src/fedlex_tax_scraper.rb
```

Or:

```sh
./run.sh
```

The scraper can be interrupted with Ctrl+C at any time. Re-run the same command to resume where it left off.

## Output

All output is written to the `output/` directory:

| File | Description |
|------|-------------|
| `output/laws/*.md` | One Markdown file per law, with YAML front matter |
| `output/swiss_federal_tax_laws_FULLTEXT.md` | Single compiled file containing all laws |
| `output/scraper.log` | Timestamped log |
| `output/state.json` | Progress tracker (delete to re-scrape everything) |

## Configuration

All settings live in `src/config.rb`. Open the file and change the constants directly:

| Constant | Default | Description |
|----------|---------|-------------|
| `OUTPUT_DIR` | `output/` | Root directory for all output files |
| `LAWS_DIR` | `output/laws/` | Directory for individual law Markdown files |
| `LAWS_FORMATTED_DIR` | `output/laws_formatted/` | Directory for cleaned/formatted law files |
| `LOG_FILE` | `output/scraper.log` | Log file path |
| `STATE_FILE` | `output/state.json` | Progress tracker (delete to re-scrape everything) |
| `MASTER_FILE` | `output/swiss_federal_tax_laws_FULLTEXT.md` | Combined file with all laws |
| `SPARQL_ENDPOINT` | `https://fedlex.data.admin.ch/sparqlendpoint` | Fedlex SPARQL API endpoint |
| `FEDLEX_BASE` | `https://fedlex.data.admin.ch` | Base URL for fetching law texts |
| `REQUEST_DELAY` | `2.0` | Seconds to wait between HTTP requests |
| `MAX_RETRIES` | `3` | Number of retries for failed requests |
| `HTTP_TIMEOUT` | `30` | HTTP request timeout in seconds |

The list of laws to scrape is defined in `src/known_laws.rb`. You can add or remove entries there to change which laws are fetched. Each entry needs a `name`, `sr` (systematic number), `cc` (consolidated-classification path), and `description`.

## Running tests

```sh
bundle exec rspec
```
