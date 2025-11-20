namespace :scrapers do
  desc "Scrape advanced team stats for current season"
  task team_advanced_stats: :environment do
    season = Season.find_by(current: true)

    if season.nil?
      puts "❌ No current season found."
      next
    end

    # Run scraper
    Scrapers::TeamAdvancedStatsScraper.new(season).scrape

    # Now apply league-wide rankings
    puts "📊 Generating league-wide stat rankings..."
    TeamAdvancedStatsRanker.new(season).generate_rankings
    puts "✔ Rankings updated."
  end
end
