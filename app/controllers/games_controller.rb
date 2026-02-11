require "#{Rails.root}/app/services/scrapers/box_score_scraper"

class GamesController < ApplicationController
  before_action :set_current_season
  before_action :set_game, only: [:show, :scrape_box_score]

  # app/controllers/games_controller.rb
  def show
    @visitor_team = @game.visitor_team
    @home_team    = @game.home_team

    @visitor_standing = Standing.find_by(team_id: @game.visitor_team_id, season_id: @current_season.id)
    @home_standing    = Standing.find_by(team_id: @game.home_team_id, season_id: @current_season.id)

    away_adv_row = TeamAdvancedStat.find_by(team: @visitor_team, season: @current_season)
    home_adv_row = TeamAdvancedStat.find_by(team: @home_team, season: @current_season)

    @away_adv  = away_adv_row&.stats || {}
    @home_adv  = home_adv_row&.stats || {}
    @away_rank = away_adv_row&.rankings || {}
    @home_rank = home_adv_row&.rankings || {}

    season_id = @current_season.id

    # -------------------------
    # Preview tables: last 5 / last 10
    # -------------------------
    players = Player.where(team_id: [@visitor_team.id, @home_team.id]).includes(:team)

    recent_box_scores = BoxScore.joins(:game)
                                .where(games: { season_id: season_id })
                                .where(player_id: players.ids)
                                .where.not(minutes_played: nil)
                                .order("games.date DESC")

    grouped_by_player = recent_box_scores.group_by(&:player_id)

    all_player_data = players.map do |player|
      box_scores = grouped_by_player[player.id] || []
      last_five  = box_scores.first(5)
      last_ten   = box_scores.first(10)

      next if last_five.empty?

      avg5  = compute_bulk_averages(last_five)
      avg10 = compute_bulk_averages(last_ten)

      if avg5[:minutes_played].to_f > 15
        { player: player, averages: avg5, last_ten_averages: avg10 }
      end
    end.compact

    @away_preview_players = all_player_data.select { |x| x[:player].team_id == @visitor_team.id }
    @home_preview_players = all_player_data.select { |x| x[:player].team_id == @home_team.id }

    # -------------------------
    # Previous meetings
    # -------------------------
    @previous_meetings = Game.where(season_id: season_id)
                            .where(
                              "(visitor_team_id = ? AND home_team_id = ?) OR (visitor_team_id = ? AND home_team_id = ?)",
                              @visitor_team.id, @home_team.id,
                              @home_team.id, @visitor_team.id
                            )
                            .where("date < ?", @game.date)
                            .order(date: :desc)

    # -------------------------
    # DvP table
    # -------------------------
    @away_dvp = @visitor_team.defense_data_for(@current_season) || {}
    @home_dvp = @home_team.defense_data_for(@current_season) || {}
    @positions = ["PG", "SG", "SF", "PF", "C"]

    # -------------------------
    # Game Simulation
    # - Distribution (Monte Carlo) for upcoming games
    # - Single deterministic sim fallback if distribution fails
    # -------------------------
    @sim_distribution = nil
    @sim_single = nil

    return if @game.date < Date.current

    begin
      sim = Simulations::GameSimulator.new(date: @game.date, season: @current_season)

      # Cached DB row (GameSimulation) containing mean score + percentiles in meta
      @sim_distribution = sim.fetch_or_simulate_distribution!(game_id: @game.id, sims: 3000)

      # Optional: also keep the single deterministic “reconciled to players” sim for the player-level totals card
      @sim_single = sim.fetch_or_simulate!(game_id: @game.id, add_noise: false)
    rescue => e
      Rails.logger.warn("[SIM] Game #{@game.id} on #{@game.date} could not be simulated: #{e.message}")
      @sim_distribution = nil
      @sim_single = nil
    end
  end



  private

  def set_game
    @game = Game.find(params[:id])
  end

  def set_current_season
    @current_season = Season.find_by(current: true)
  end

end
