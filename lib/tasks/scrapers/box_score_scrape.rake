# lib/tasks/scrapers/box_score_scrape.rake
namespace :scrapers do
  desc "Scrape box scores for games (and update defense data for current season)"
  task box_scores: :environment do
    require Rails.root.join('app/services/scrapers/box_score_scraper')

    # Identify current season
    current_season = Season.find_by(current: true)
    unless current_season
      puts "❌ No active season found. Please mark the current season as 'current: true'."
      next
    end

    previous_day = Date.yesterday
    games = Game.where(date: previous_day, season_id: current_season.id)

    if games.any?
      puts "🏀 Starting box score scraping for #{games.count} games from #{previous_day} (Season: #{current_season.name})"

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

      # Update DefenseVsPosition data for all teams in the current season
      puts "📊 Rebuilding Defense vs Position data for all teams (#{current_season.name})..."
      Team.find_each do |team|
        team.rebuild_defense_vs_position!(current_season)
      end
      puts "✅ Defense vs Position data updated successfully for #{current_season.name}."

    else
      puts "ℹ️ No games found for #{previous_day} (Season: #{current_season.name})"
    end
  end
end
