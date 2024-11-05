class StandingsController < ApplicationController
  def index
    @eastern_standings = Standing.where(season: 2025, conference: 'Eastern').order(win_percentage: :desc)
    @western_standings = Standing.where(season: 2025, conference: 'Western').order(win_percentage: :desc)
  end

  def update
    Scrapers::StandingsScraper.new.scrape
    redirect_to standings_path, notice: "Standings have been updated."
  end
end
