require "#{Rails.root}/app/services/scrapers/box_score_scraper"


class GamesController < ApplicationController

  before_action :set_game, only: [:show, :scrape_box_score]

  def show
    @game = Game.find(params[:id])
    @visitor_team = @game.visitor_team
    @home_team = @game.home_team
    @visitor_team_players = @visitor_team.players.includes(:player_stat) # Assuming players and player_stats associations
    @home_team_players = @home_team.players.includes(:player_stat) # Assuming players and player_stats associations
  end


  def scrape_box_score
    if Scrapers::BoxScoreScraper.new(@game).scrape_box_score
      flash[:notice] = "Box score updated successfully."
    else
      flash[:alert] = "Failed to update box score."
    end
    redirect_to game_path(@game)
  end

  def scrape_previous_day_games
    previous_day = Date.yesterday
    games = Game.where(date: previous_day)

    if games.any?
      games.each_with_index do |game, index|
        ScrapeBoxScoresJob.set(wait: index * 30.seconds).perform_later(game.id)
      end
      flash[:notice] = "Scheduled box score scrapes for #{games.count} games on #{previous_day.strftime('%B %d, %Y')}"
    else
      flash[:alert] = "No games found for #{previous_day.strftime('%B %d, %Y')}"
    end

    redirect_to root_path
  end

  def scrape_date_range_games
    start_date = Date.parse("2024-10-22")
    end_date = Date.parse("2024-11-06")

    ScrapeBoxScoresDateRangeJob.perform_later(start_date, end_date)
    flash[:notice] = "Scheduled box score scrapes for games between #{start_date.strftime('%B %d, %Y')} and #{end_date.strftime('%B %d, %Y')}"
    
    redirect_to root_path
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end


end
