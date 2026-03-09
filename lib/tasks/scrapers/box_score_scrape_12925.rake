namespace :scrapers do
  desc "Backfill advanced box scores for Game IDs 1340–1407"
  task backfill_box_scores_1340_1407: :environment do
    require Rails.root.join('app/services/scrapers/box_score_scraper')

    current_season = Season.find_by(current: true)
    unless current_season
      puts "❌ No active season found. Please mark the current season as 'current: true'."
      next
    end

    start_id = 2509
    end_id   = 2520

    games = Game.where(id: start_id..end_id, season_id: current_season.id).order(:id)

    if games.any?
      puts "🏀 Starting backfill for #{games.count} games (IDs #{start_id}–#{end_id})"
      puts "Season: #{current_season.name}"

      games.each_with_index do |game, index|
        puts "➡️ [#{index + 1}/#{games.count}] Scraping Game ID #{game.id} - #{game.visitor_team.name} @ #{game.home_team.name}"

        scraper = Scrapers::BoxScoreScraper.new(game)
        success = scraper.scrape_box_score

        if success
          puts "✅ Updated Game ID #{game.id}"
        else
          puts "⚠️ Failed Game ID #{game.id}"
        end

        # Small sleep between requests to avoid being blocked
        sleep(25) unless index == games.size - 1
      end

      puts "✅ Finished backfilling advanced box scores for #{games.count} games."
    else
      puts "ℹ️ No games found in ID range #{start_id}–#{end_id}"
    end
  end
end
