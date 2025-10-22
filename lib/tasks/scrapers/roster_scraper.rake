# lib/tasks/scrapers/roster_scraper.rake
namespace :scrapers do
  desc "Scrape rosters for all teams"
  task scrape_rosters: :environment do
    Team.find_each do |team|
      puts "Scraping roster for #{team.name} (#{team.abbreviation})"
      Scrapers::RosterScraper.new(team.abbreviation, team.id).scrape
    end
    puts "Roster scraping completed."
  end
end
