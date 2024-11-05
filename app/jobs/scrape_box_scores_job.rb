class ScrapeBoxScoresJob < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    # Perform the box score scrape
    if Scrapers::BoxScoreScraper.new(game).scrape_box_score
      puts "Successfully scraped box score for Game ID: #{game.id}"
    else
      puts "Failed to scrape box score for Game ID: #{game.id}"
    end
  end
end


