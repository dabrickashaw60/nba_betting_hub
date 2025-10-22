namespace :scrape do
  desc "Scrape NBA schedule for the 2025 season"
  task schedule: :environment do
    puts "Starting schedule scraping..."
    Scrapers::ScheduleScraper.scrape_schedule
    puts "Schedule scraping completed."
  end
end
