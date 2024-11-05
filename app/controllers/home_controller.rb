class HomeController < ApplicationController
  def index
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @todays_games = Game.where(date: @date)
    @standings = Standing.where(season: 2025).includes(:team).order(win_percentage: :desc)
  end

  def update_schedule
    month = params[:month]
    Scrapers::ScheduleScraper.scrape_schedule(month)
    redirect_to root_path, notice: "#{month} schedule updated successfully."
  end

end
