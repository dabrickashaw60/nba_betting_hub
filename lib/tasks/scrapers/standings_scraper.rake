namespace :scrapers do
  desc "Scrape NBA team standings for Western and Eastern Conferences"
  task scrape_standings: :environment do
    Scrapers::StandingsScraper.new.scrape
  end
end