# app/jobs/scrape_box_scores_date_range_job.rb
class ScrapeBoxScoresDateRangeJob < ApplicationJob
  queue_as :default

  def perform(start_date, end_date)
    (start_date..end_date).each do |date|
      games = Game.where(date: date)
      
      games.each_with_index do |game, index|
        # Schedule each game's scraping with a 20-second delay
        ScrapeBoxScoresJob.set(wait: index * 20.seconds).perform_later(game.id)
      end
    end

    Team.update_defense_averages

  end
end
