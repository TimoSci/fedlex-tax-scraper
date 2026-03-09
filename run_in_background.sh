nohup ruby fedlex_tax_scraper.rb > /dev/null 2>&1 &
tail -f output/scraper.log   # watch progress in another terminal
