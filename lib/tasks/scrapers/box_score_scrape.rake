# lib/tasks/scrapers/box_score_scrape.rake
namespace :scrapers do
  desc "Scrape box scores for games"
  task box_scores: :environment do
    require Rails.root.join('app/services/scrapers/box_score_scraper')

    # Example: Scraping games for the previous day
    previous_day = Date.yesterday
    games = Game.where(date: previous_day)

    if games.any?
      Rails.logger.info "Starting box score scraping for #{games.count} games from #{previous_day}"

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
      Rails.logger.info "No games found for #{previous_day}"
    end
  end
end
