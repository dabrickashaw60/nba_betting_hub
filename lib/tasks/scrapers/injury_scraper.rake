namespace :scraper do
  desc "Scrape and update player injuries"
  task update_injuries: :environment do
    require Rails.root.join('app/services/scrapers/injury_scraper') # Load your scraper

    # Call the scraper
    Scrapers::InjuryScraper.scrape_and_update_injuries
  end
end
