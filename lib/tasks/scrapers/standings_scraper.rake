namespace :scrapers do
  desc "Scrape NBA team standings for Western and Eastern Conferences"
  task scrape_standings: :environment do
    # Get the current season
    current_season = Season.find_by(current: true)

    if current_season.nil?
      puts "❌ No active season found. Please mark the current season as 'current: true'."
      next
    end

    puts "🏀 Starting standings scrape for #{current_season.name}..."
    Scrapers::StandingsScraper.new(current_season.id).scrape
    puts "✅ Standings scrape completed for #{current_season.name}."
  end
end
