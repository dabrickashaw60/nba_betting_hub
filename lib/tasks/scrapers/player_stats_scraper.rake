# lib/tasks/scrapers/player_stats_scraper.rake
namespace :scrapers do
  desc "Scrape player stats for all players in each team's roster"
  task scrape_player_stats: :environment do
    puts "Starting player stats scraping for all teams..."

    Team.find_each do |team|
      puts "Scraping player stats for team #{team.name} (#{team.abbreviation})..."
      scraper = Scrapers::PlayerStatsScraper.new(team.abbreviation, team.id)
      scraper.scrape
    end

    puts "Player stats scraping completed for all teams."
  end
end
