require "#{Rails.root}/app/services/scrapers/box_score_scraper"


class GamesController < ApplicationController

  before_action :set_game, only: [:show, :scrape_box_score]

  def show
    @game = Game.find(params[:id])
    @visitor_team = @game.visitor_team
    @home_team = @game.home_team
    @visitor_team_players = @visitor_team.players.includes(:box_scores).sort_by do |player|
      (player.try(:last_five_average) || { minutes_played: 0 })[:minutes_played].to_f
    end
    
    @home_team_players = @home_team.players.includes(:box_scores).sort_by do |player|
      (player.try(:last_five_average) || { minutes_played: 0 })[:minutes_played].to_f
    end
    
    
  
    # Initialize the betting info hash
    @betting_info = {}
  
    # Calculate last five-game averages and betting info for each player in both teams
    [@visitor_team_players, @home_team_players].each do |team_players|
      team_players.each do |player|
        last_five_games = player.box_scores.joins(:game).order('games.date DESC').limit(5)
  
        # Store last five averages on each player
        last_five_averages = {
          minutes_played: calculate_average_minutes(last_five_games),
          points: average_stat(last_five_games, :points),
          rebounds: average_stat(last_five_games, :total_rebounds),
          assists: average_stat(last_five_games, :assists),
          field_goals: average_stat(last_five_games, :field_goals),
          field_goals_attempted: average_stat(last_five_games, :field_goals_attempted),
          field_goal_percentage: average_percentage(last_five_games, :field_goals, :field_goals_attempted),
          three_point_field_goals: average_stat(last_five_games, :three_point_field_goals),
          three_point_field_goals_attempted: average_stat(last_five_games, :three_point_field_goals_attempted),
          three_point_percentage: average_percentage(last_five_games, :three_point_field_goals, :three_point_field_goals_attempted),
          free_throws: average_stat(last_five_games, :free_throws),
          free_throws_attempted: average_stat(last_five_games, :free_throws_attempted),
          free_throw_percentage: average_percentage(last_five_games, :free_throws, :free_throws_attempted),
          steals: average_stat(last_five_games, :steals),
          blocks: average_stat(last_five_games, :blocks),
          turnovers: average_stat(last_five_games, :turnovers),
          personal_fouls: average_stat(last_five_games, :personal_fouls),
          plus_minus: average_stat(last_five_games, :plus_minus)
        }
  
        # Define last five averages as a singleton method on the player
        player.define_singleton_method(:last_five_average) do
          last_five_averages
        end
  
        # Betting info calculation for each player
        @betting_info[player.id] = {
          points: count_thresholds(last_five_games, :points, [10, 15, 20, 25, 30]),
          threes: count_thresholds(last_five_games, :three_point_field_goals, [1, 2, 3, 4, 5]),
          rebounds: count_thresholds(last_five_games, :total_rebounds, [2, 4, 6, 8, 10]),
          assists: count_thresholds(last_five_games, :assists, [2, 4, 6, 8, 10])
        }
      end
    end
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
    start_date = Date.parse("2024-11-15")
    end_date = Date.parse("2024-11-16")

    ScrapeBoxScoresDateRangeJob.perform_later(start_date, end_date)
    flash[:notice] = "Scheduled box score scrapes for games between #{start_date.strftime('%B %d, %Y')} and #{end_date.strftime('%B %d, %Y')}"
    
    redirect_to root_path
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def average_stat(games, stat)
    return 0 if games.empty?
    games.sum(&stat).to_f / games.size
  end

  def calculate_average_minutes(games)
    valid_games = games.select { |game| game.minutes_played.present? }
    return "00:00" if valid_games.empty?
  
    total_seconds = valid_games.sum do |game|
      minutes, seconds = game.minutes_played.split(":").map(&:to_i)
      (minutes * 60) + seconds
    end
  
    average_seconds = total_seconds / valid_games.size
    minutes = average_seconds / 60
    seconds = average_seconds % 60
    format("%02d:%02d", minutes, seconds)
  end
  

  def average_percentage(games, made_stat, attempted_stat)
    total_made = games.sum(&made_stat)
    total_attempted = games.sum(&attempted_stat)
    return 0.0 if total_attempted.zero?
    (total_made.to_f / total_attempted).round(3)
  end

  def count_thresholds(games, stat, thresholds)
    thresholds.map do |threshold|
      games.count { |game| game.send(stat) >= threshold }
    end
  end

end
