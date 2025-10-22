require "#{Rails.root}/app/services/scrapers/box_score_scraper"

class GamesController < ApplicationController
  before_action :set_current_season
  before_action :set_game, only: [:show, :scrape_box_score]

  # ---------------------------------------------------------------------------
  # 🏀 SHOW: Display a single game’s box scores, averages, betting info, etc.
  # ---------------------------------------------------------------------------
  def show
    @visitor_team = @game.visitor_team
    @home_team    = @game.home_team

    # Filter by the current season for all data
    season_id = @current_season.id

    # Sort visitor/home players by their last 5 average minutes (season-specific)
    @visitor_team_players = @visitor_team.players.includes(:box_scores).sort_by do |player|
      -((player.try(:last_five_average, season_id) || { minutes_played: 0 })[:minutes_played].to_f)
    end

    @home_team_players = @home_team.players.includes(:box_scores).sort_by do |player|
      -((player.try(:last_five_average, season_id) || { minutes_played: 0 })[:minutes_played].to_f)
    end

    # All recent game logs for both teams (filtered by season)
    @game_logs = BoxScore
                   .joins(:game, :player)
                   .where(players: { team_id: [@visitor_team.id, @home_team.id] })
                   .where(games: { season_id: season_id })
                   .where.not(minutes_played: nil)
                   .order('games.date DESC')

    @last_five_games = @game_logs.limit(5)
    @last_ten_games  = @game_logs.limit(10)

    # Team-wide last 5 averages
    @last_five_averages = build_averages(@last_five_games)
    @last_ten_averages  = build_averages(@last_ten_games)

    # Collect all players (for dropdowns, etc.)
    @players = @visitor_team.players + @home_team.players
    @relevant_positions = %w[PG SG SF PF C G F]

    # Betting info container
    @betting_info = {}

    # Calculate last-five-game averages and betting info per player (season-specific)
    [@visitor_team_players, @home_team_players].each do |team_players|
      team_players.each do |player|
        last_five_games = player.box_scores
                                .joins(:game)
                                .where(games: { season_id: season_id })
                                .order('games.date DESC')
                                .limit(5)

        # Store averages
        last_five_averages = build_player_averages(last_five_games)
        player.define_singleton_method(:last_five_average) { last_five_averages }

        # Store betting thresholds
        @betting_info[player.id] = {
          points:   count_thresholds(last_five_games, :points, [10, 15, 20, 25, 30]),
          threes:   count_thresholds(last_five_games, :three_point_field_goals, [1, 2, 3, 4, 5]),
          rebounds: count_thresholds(last_five_games, :total_rebounds, [2, 4, 6, 8, 10]),
          assists:  count_thresholds(last_five_games, :assists, [2, 4, 6, 8, 10])
        }
      end
    end

    # Opponent defense per team
    @defense_vs_position_by_team = {
      @home_team.id    => @home_team.opponent_defense_for_game(@game),
      @visitor_team.id => @visitor_team.opponent_defense_for_game(@game)
    }
  end

  # ---------------------------------------------------------------------------
  # 📊 SCRAPING ACTIONS
  # ---------------------------------------------------------------------------

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
    games = Game.where(date: previous_day, season_id: @current_season.id)

    if games.any?
      games.each_with_index do |game, index|
        ScrapeBoxScoresJob.set(wait: index * 30.seconds).perform_later(game.id)
      end
      flash[:notice] = "Scheduled scrapes for #{games.count} games on #{previous_day.strftime('%B %d, %Y')}."
    else
      flash[:alert] = "No games found for #{previous_day.strftime('%B %d, %Y')}."
    end

    redirect_to root_path
  end

  def scrape_date_range_games
    start_date = Date.parse("2025-05-24")
    end_date   = Date.parse("2025-05-25")

    games = Game.where(date: start_date..end_date, season_id: @current_season.id)

    if games.any?
      games.each_with_index do |game, index|
        ScrapeBoxScoresJob.set(wait: index * 30.seconds).perform_later(game.id)
      end
      flash[:notice] = "Scheduled scrapes for #{games.count} games from #{start_date.strftime('%b %d')} to #{end_date.strftime('%b %d, %Y')}."
    else
      flash[:alert] = "No games found in that date range."
    end

    redirect_to root_path
  end

  # ---------------------------------------------------------------------------
  # 🧮 HELPER METHODS
  # ---------------------------------------------------------------------------

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def set_current_season
    @current_season = Season.find_by(current: true)
  end

  def build_averages(games)
    {
      minutes_played: calculate_average_minutes(games),
      points: average_stat(games, :points),
      rebounds: average_stat(games, :total_rebounds),
      assists: average_stat(games, :assists),
      field_goals: average_ratio(games, :field_goals, :field_goals_attempted),
      three_pointers: average_ratio(games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: average_ratio(games, :free_throws, :free_throws_attempted),
      plus_minus: average_stat(games, :plus_minus),
      steals: average_stat(games, :steals),
      blocks: average_stat(games, :blocks),
      turnovers: average_stat(games, :turnovers),
      personal_fouls: average_stat(games, :personal_fouls)
    }
  end

  def build_player_averages(games)
    {
      minutes_played: calculate_average_minutes(games),
      points: average_stat(games, :points),
      rebounds: average_stat(games, :total_rebounds),
      assists: average_stat(games, :assists),
      field_goals: average_stat(games, :field_goals),
      field_goals_attempted: average_stat(games, :field_goals_attempted),
      field_goal_percentage: average_percentage(games, :field_goals, :field_goals_attempted),
      three_point_field_goals: average_stat(games, :three_point_field_goals),
      three_point_field_goals_attempted: average_stat(games, :three_point_field_goals_attempted),
      three_point_percentage: average_percentage(games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: average_stat(games, :free_throws),
      free_throws_attempted: average_stat(games, :free_throws_attempted),
      free_throw_percentage: average_percentage(games, :free_throws, :free_throws_attempted),
      steals: average_stat(games, :steals),
      blocks: average_stat(games, :blocks),
      turnovers: average_stat(games, :turnovers),
      personal_fouls: average_stat(games, :personal_fouls),
      plus_minus: average_stat(games, :plus_minus)
    }
  end

  def average_stat(games, stat)
    return 0 if games.empty?
    games.sum(&stat).to_f / games.size
  end

  def calculate_average_minutes(games)
    valid_games = games.select { |g| g.minutes_played.present? }
    return "00:00" if valid_games.empty?

    total_seconds = valid_games.sum do |g|
      m, s = g.minutes_played.split(":").map(&:to_i)
      (m * 60) + s
    end

    avg_seconds = total_seconds / valid_games.size
    minutes = avg_seconds / 60
    seconds = avg_seconds % 60
    format("%02d:%02d", minutes, seconds)
  end

  def average_ratio(games, made, att)
    made_sum = games.sum(&made)
    att_sum  = games.sum(&att)
    return "0.0 / 0.0" if att_sum.zero?
    "#{(made_sum.to_f / games.size).round(1)}/#{(att_sum.to_f / games.size).round(1)}"
  end

  def average_percentage(games, made, att)
    made_sum = games.sum(&made)
    att_sum  = games.sum(&att)
    return 0.0 if att_sum.zero?
    (made_sum.to_f / att_sum).round(3)
  end

  def count_thresholds(games, stat, thresholds)
    thresholds.map { |t| games.count { |g| g.send(stat) >= t } }
  end
end
