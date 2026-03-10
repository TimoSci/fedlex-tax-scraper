# Paths, endpoints, and tuning constants shared across all modules.
OUTPUT_DIR   = File.join(__dir__, '..', 'output')
LAWS_DIR     = File.join(OUTPUT_DIR, 'laws')
LOG_FILE     = File.join(OUTPUT_DIR, 'scraper.log')
STATE_FILE   = File.join(OUTPUT_DIR, 'state.json')
MASTER_FILE  = File.join(OUTPUT_DIR, 'swiss_federal_tax_laws_FULLTEXT.md')

SPARQL_ENDPOINT = 'https://fedlex.data.admin.ch/sparqlendpoint'
FEDLEX_BASE     = 'https://fedlex.data.admin.ch'

# Delay between HTTP requests (seconds). Be a polite scraper.
REQUEST_DELAY = 2.0

# Max retries per request
MAX_RETRIES = 3

# HTTP timeout (seconds)
HTTP_TIMEOUT = 30
