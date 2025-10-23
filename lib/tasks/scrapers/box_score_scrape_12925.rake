namespace :scrapers do
  desc "Scrape box scores for games on a specific date (e.g., Jan 29, 2025)"
  task box_scores_12925: :environment do
    require Rails.root.join('app/services/scrapers/box_score_scraper')

    # Identify current season
    current_season = Season.find_by(current: true)
    unless current_season
      puts "❌ No active season found. Please mark the current season as 'current: true'."
      next
    end

    # 👇 Change this to the exact date you want
    specific_date = Date.new(2025, 10, 21)

    games = Game.where(date: specific_date, season_id: current_season.id)

    if games.any?
      puts "🏀 Starting box score scraping for #{games.count} games from #{specific_date} (Season: #{current_season.name})"

      games.each_with_index do |game, index|
        puts "➡️ Scraping Game ID #{game.id} (#{index + 1}/#{games.count}) - #{game.visitor_team.name} @ #{game.home_team.name}"

        scraper = Scrapers::BoxScoreScraper.new(game)
        if scraper.scrape_box_score
          puts "✅ Successfully scraped Game ID: #{game.id}"
        else
          puts "⚠️ Failed to scrape Game ID: #{game.id}"
        end

        # Space out requests slightly
        sleep(30) unless index == games.size - 1
      end

      # Rebuild defense vs position data for current season
      puts "📊 Rebuilding Defense vs Position data for all teams (#{current_season.name})..."
      Team.find_each do |team|
        team.rebuild_defense_vs_position!(current_season)
      end
      puts "✅ Defense vs Position data updated successfully for #{current_season.name}."

    else
      puts "ℹ️ No games found for #{specific_date} (Season: #{current_season.name})"
    end
  end
end
