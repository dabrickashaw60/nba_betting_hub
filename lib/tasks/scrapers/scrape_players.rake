# lib/tasks/scrapers/scrape_players.rake

namespace :scrapers do
  desc 'Scrape NBA players'
  task scrape_players: :environment do
    puts "Starting player scraping..."
    Scrapers::PlayerScraper.new.scrape
    puts "Player scraping completed."
  end
end
