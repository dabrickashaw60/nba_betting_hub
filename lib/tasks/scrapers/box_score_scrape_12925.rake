namespace :scrapers do
  desc "Scrape box scores for games on January 29, 2025"
  task box_scores_12925: :environment do
    require Rails.root.join('app/services/scrapers/box_score_scraper')

    specific_date = Date.new(2025, 4, 19) # Hardcoded to 4/11/25
    games = Game.where(date: specific_date)

    if games.any?
      Rails.logger.info "Starting box score scraping for #{games.count} games from #{specific_date}"

      games.each_with_index do |game, index|
        Rails.logger.info "Scraping Game ID: #{game.id} (#{index + 1}/#{games.count})"

        scraper = Scrapers::BoxScoreScraper.new(game)
        if scraper.scrape_box_score
          Rails.logger.info "Successfully scraped Game ID: #{game.id}"
        else
          Rails.logger.warn "Failed to scrape Game ID: #{game.id}"
        end

        # Space out the scraping to avoid overloading the source
        sleep(30) unless index == games.size - 1
      end

      # Update defense averages after scraping all games
      Rails.logger.info "Updating defense averages for all teams..."
      Team.update_defense_averages
      Rails.logger.info "Defense averages updated successfully."

    else
      Rails.logger.info "No games found for #{specific_date}"
    end
  end
end
