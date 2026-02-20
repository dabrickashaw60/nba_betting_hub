require "#{Rails.root}/app/services/scrapers/box_score_scraper"

class GamesController < ApplicationController
  before_action :set_current_season
  before_action :set_game, only: [:show, :scrape_box_score]

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
    # Preview tables: ALL PLAYERS WITH PROJECTIONS for this game
    # (no minutes cutoff)
    # -------------------------
    player_mc_model = Projections::DistributionSimulator::MODEL_VERSION # "proj_mc_v1"

    team_ids = [@visitor_team.id, @home_team.id]

    # Baseline projections for this specific matchup (this defines "has projections")
    proj_rows = Projection
      .where(date: @game.date, team_id: team_ids)
      .where(opponent_team_id: team_ids)

    proj_by_player_id = proj_rows.index_by(&:player_id)

    # Only include players that actually have a projection row
    projected_player_ids = proj_rows.map(&:player_id).compact.uniq

    players = Player.where(id: projected_player_ids).includes(:team)

    # MC distribution means for the same matchup (optional per player)
    dist_rows = ProjectionDistribution
      .where(
        date: @game.date,
        team_id: team_ids,
        opponent_team_id: team_ids,
        model_version: player_mc_model,
        player_id: projected_player_ids
      )

    dist_by_player_id = dist_rows.index_by(&:player_id)

    all_proj_preview =
      players.map do |p|
        proj = proj_by_player_id[p.id]
        next if proj.nil? # safety

        dist = dist_by_player_id[p.id]

        exp_min =
          if dist&.minutes_mean.present?
            dist.minutes_mean.to_f
          else
            proj.expected_minutes.to_f
          end

        {
          player: p,
          projection: proj,
          distribution: dist,
          minutes: exp_min
        }
      end

    @away_preview_players = all_proj_preview
      .select { |x| x[:player].team_id == @visitor_team.id }
      .sort_by { |x| -x[:minutes].to_f }

    @home_preview_players = all_proj_preview
      .select { |x| x[:player].team_id == @home_team.id }
      .sort_by { |x| -x[:minutes].to_f }

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
    # Game Lines (DETERMINISTIC)
    # Built from ProjectionDistribution.points_mean sums.
    # No game Monte Carlo here.
    # -------------------------
    @sim_distribution = nil
    @sim_single = nil

    return if @game.date < Date.current

    begin
      model_version = Simulations::GameFromPlayerMeans::MODEL_VERSION

      @sim_distribution =
        GameSimulation.find_by(
          date: @game.date,
          game_id: @game.id,
          model_version: model_version
        )

      unless @sim_distribution
        builder = Simulations::GameFromPlayerMeans.new(
          date: @game.date,
          season: @current_season,
          player_model_version: player_mc_model
        )

        builder.build!(game_id: @game.id, persist: true)

        @sim_distribution =
          GameSimulation.find_by(
            date: @game.date,
            game_id: @game.id,
            model_version: model_version
          )
      end

      @sim_single = nil
    rescue => e
      Rails.logger.warn("[SIM] Game #{@game.id} on #{@game.date} could not be built from player means: #{e.message}")
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
