# app/controllers/projections_controller.rb
class ProjectionsController < ApplicationController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @current_season = Season.find_by(current: true)
    @run = ProjectionRun.where(date: @date, model_version: Projections::BaselineModel::MODEL_VERSION)
                    .order(created_at: :desc)
                    .first
    season_id = Season.find_by(current: true)&.id

    @projections = Projection.includes(:player, :team)
                            .where(date: @date)
                            .map do |proj|
    last5 = proj.player.box_scores
              .joins(:game)
              .where(games: { season_id: season_id })
              .where.not(minutes_played: [nil, ""])
              .order("games.date DESC")
              .limit(5)

    # --- Helper method to calculate average minutes (copied from PlayersController) ---
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

    # --- Usage % average ---
    usage_values = last5.pluck(:usage_pct).compact.map(&:to_f)
    avg_usage = usage_values.any? ? (usage_values.sum / usage_values.size).round(1) : 0.0

    # --- Build last5 averages hash ---
    last5_avg = {
      points:          last5.average(:points).to_f.round(1),
      rebounds:        last5.average(:total_rebounds).to_f.round(1),
      assists:         last5.average(:assists).to_f.round(1),
      usage_pct:       avg_usage,
      minutes_played:  calculate_average_minutes(last5)
    }

      {
        projection: proj,
        last5_avg: last5_avg
      }
    end
  end

  def results
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @season = Season.find_by(current: true)
    raise "No current season" unless @season

    @games = Game.where(date: @date, season_id: @season.id)
                 .includes(:home_team, :visitor_team)
                 .order(:time)

    @selected_game = nil
    @box_scores = []
    @proj_by_player_id = {}

    if params[:game_id].present?
      @selected_game = @games.find { |g| g.id == params[:game_id].to_i }

      if @selected_game
        # Actuals (box score)
        @box_scores = BoxScore.where(game_id: @selected_game.id)
                              .includes(:player, :team)
                              .to_a

        # Projections: match by same date + same two teams
        team_ids = [@selected_game.home_team_id, @selected_game.visitor_team_id]

        projections = Projection.where(date: @date)
                                .where(team_id: team_ids)
                                .where(opponent_team_id: team_ids)
                                .to_a

        @proj_by_player_id = projections.index_by(&:player_id)
      end
    end
  end

  def debug_player
    date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    player = Player.find(params[:player_id])

    model = Projections::BaselineModel.new(date: date)
    debug = model.debug_player!(player.id)

    saved = Projection.find_by(date: date, player_id: player.id)
    saved_attrs = saved&.attributes&.slice(
      "projection_run_id",
      "expected_minutes",
      "usage_pct",
      "assist_pct",
      "rebound_pct",
      "proj_points",
      "proj_rebounds",
      "proj_assists",
      "updated_at"
    )

    runs = ProjectionRun.where(date: date).order(updated_at: :desc).limit(10)
                        .pluck(:model_version, :status, :projections_count, :updated_at)

    render json: {
      date: date,
      player: { id: player.id, name: player.name, team_id: player.team_id, position: player.position },
      saved_projection: saved_attrs,
      projection_runs: runs,
      baseline_debug: debug
    }
  end
  

  def show
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @projection = Projection.includes(:player, :team, :opponent_team)
                            .find_by!(date: @date, player_id: params[:id])
  end

  def generate
    date = params[:date].present? ? Date.parse(params[:date]) : Date.today

    # Delete projections FIRST (FK constraint), then delete baseline runs
    Projection.where(date: date).delete_all
    ProjectionRun.where(date: date, model_version: Projections::BaselineModel::MODEL_VERSION).delete_all

    run = Projections::BaselineModel.new(date: date).run!

    redirect_to projections_path(date: date),
                notice: "Projections re-run completed with #{run.projections_count} players."
  end

end

