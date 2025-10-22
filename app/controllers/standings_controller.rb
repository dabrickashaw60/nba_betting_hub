class StandingsController < ApplicationController
  before_action :set_current_season

  def index
    @eastern_standings = Standing.where(season_id: @current_season.id, conference: 'Eastern')
                                 .includes(:team)
                                 .order(win_percentage: :desc)

    @western_standings = Standing.where(season_id: @current_season.id, conference: 'Western')
                                 .includes(:team)
                                 .order(win_percentage: :desc)
  end

  def update
    Scrapers::StandingsScraper.new(@current_season.id).scrape
    redirect_to standings_path, notice: "Standings updated for #{@current_season.name}."
  end

  private

  def set_current_season
    @current_season = Season.find_by(current: true)
  end
end
