class ScrapeBoxScoresJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    begin
      # Perform the box score scrape
      scraper = Scrapers::BoxScoreScraper.new(game)
      if scraper.scrape_box_score
        Rails.logger.info "Successfully scraped box score for Game ID: #{game.id}"
      else
        Rails.logger.warn "Failed to scrape box score for Game ID: #{game.id} - Box score not found or incomplete."
      end
    rescue StandardError => e
      Rails.logger.error "Error scraping box score for Game ID: #{game.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    Team.update_defense_averages

  end
end
