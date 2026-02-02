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
    @date   = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @season = Season.find_by(current: true)

    # Safe defaults
    @games             = []
    @selected_game     = nil
    @box_scores        = []
    @proj_by_player_id = {}

    @day_missing_projection_count = 0
    @day_missing_projection_players = []  # optional for display
    @game_missing_projection_count = 0
    @game_missing_projection_players = [] # optional for display

    # Metrics:
    # - @day_metric_boxes = full-day across all games on @date
    # - @metric_boxes     = selected game only
    @day_metric_boxes  = {}
    @metric_boxes      = {}

    if @season
      @games = Game.where(date: @date, season_id: @season.id)
                  .includes(:home_team, :visitor_team)
                  .order(:time)
                  .to_a
    else
      Rails.logger.warn "[PROJECTIONS RESULTS] No current season set."
    end

    Rails.logger.info "[PROJECTIONS RESULTS] date param=#{params[:date].inspect}"
    Rails.logger.info "[PROJECTIONS RESULTS] parsed date=#{@date.inspect}"
    Rails.logger.info "[PROJECTIONS RESULTS] season_id=#{@season&.id} current=#{@season&.current}"
    Rails.logger.info "[PROJECTIONS RESULTS] games count=#{@games.size}"

    # ------------------------------------------------------------
    # FULL DAY METRICS (across all games on the date)
    # ------------------------------------------------------------
    if @games.any?
      day_game_ids = @games.map(&:id)
      day_team_ids = @games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.compact.uniq

      day_box_scores = BoxScore.where(game_id: day_game_ids)
                              .includes(:player, :team)
                              .to_a

      day_projections = Projection.where(date: @date)
                                  .where(team_id: day_team_ids)
                                  .where(opponent_team_id: day_team_ids)
                                  .to_a

      day_proj_by_player_id = day_projections.index_by(&:player_id)

      minutes_cutoff = 10

      day_missing = day_box_scores.select do |bs|
        bs.minutes_played.to_f >= minutes_cutoff && day_proj_by_player_id[bs.player_id].nil?
      end

      @day_missing_projection_count = day_missing.size
      @day_missing_projection_players = day_missing.map do |bs|
        {
          player_name: bs.player&.name,
          team: bs.team&.abbreviation,
          minutes: bs.minutes_played.to_f
        }
      end

      @day_metric_boxes = build_metric_boxes(day_box_scores, day_proj_by_player_id, minutes_threshold: 0)
    end

    # ------------------------------------------------------------
    # QUICK GUIDE SCOPE (dropdown-driven)
    # ------------------------------------------------------------
    @guide_scope = params[:scope].presence || "day"

    today = Date.today
    range =
      case @guide_scope
      when "overall"
        # current season to today (safe default)
        Game.where(season_id: @season.id).minimum(:date)..today
      when "last3"
        (today - 2)..today
      when "last7"
        (today - 6)..today
      else
        # "day"
        @date..@date
      end

    guide_games = if @season
      Game.where(season_id: @season.id, date: range)
          .includes(:home_team, :visitor_team)
          .to_a
    else
      []
    end

    @guide_metric_boxes = {}
    @guide_missing_projection_count = 0

    if guide_games.any?
      @guide_metric_boxes, @guide_missing_projection_count =
        build_metrics_for_games(guide_games, minutes_threshold: 0, missing_minutes_cutoff: 10)
    end

    # Keep your existing day metrics if you still want them separately:
    # @day_metric_boxes is no longer needed for the top guide if you swap the view to @guide_metric_boxes


    # ------------------------------------------------------------
    # SELECTED GAME (table + per-game metrics)
    # ------------------------------------------------------------
    if params[:game_id].present? && @games.any?
      @selected_game = @games.find { |g| g.id == params[:game_id].to_i }

      if @selected_game
        @box_scores = BoxScore.where(game_id: @selected_game.id)
                              .includes(:player, :team)
                              .to_a

        team_ids = [@selected_game.home_team_id, @selected_game.visitor_team_id].compact

        projections = Projection.where(date: @date)
                                .where(team_id: team_ids)
                                .where(opponent_team_id: team_ids)
                                .to_a

        @proj_by_player_id = projections.index_by(&:player_id)

        minutes_cutoff = 10

        game_missing = @box_scores.select do |bs|
          bs.minutes_played.to_f >= minutes_cutoff && @proj_by_player_id[bs.player_id].nil?
        end

        @game_missing_projection_count = game_missing.size
        @game_missing_projection_players = game_missing.map do |bs|
          {
            player_name: bs.player&.name,
            team: bs.team&.abbreviation,
            minutes: bs.minutes_played.to_f
          }
        end

        # This is the metric set you already placed in the current game section
        @metric_boxes = build_metric_boxes(@box_scores, @proj_by_player_id, minutes_threshold: 0)
      end
    end
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


  private

  def build_metrics_for_games(games, minutes_threshold: 0, missing_minutes_cutoff: 10)
    game_ids = games.map(&:id)
    date_range = games.map(&:date).min..games.map(&:date).max

    # Need game loaded so we can look up bs.game.date
    box_scores = BoxScore.where(game_id: game_ids)
                        .includes(:player, :team, :game)
                        .to_a

    projections = Projection.where(date: date_range).to_a

    # IMPORTANT: must key by [date, player_id], not just player_id
    proj_by_date_player = projections.index_by { |p| [p.date, p.player_id] }

    boxes = build_metric_boxes_by_date(box_scores, proj_by_date_player, minutes_threshold: minutes_threshold)

    missing = box_scores.count do |bs|
      bs.minutes_played.to_f >= missing_minutes_cutoff &&
        proj_by_date_player[[bs.game.date, bs.player_id]].nil?
    end

    [boxes, missing]
  end

  def build_metric_boxes_by_date(box_scores, proj_by_date_player, minutes_threshold: 0)
    stat_defs = {
      min:  { label: "MIN",  actual: ->(bs) { bs.minutes_played.to_f },    proj: ->(p) { p.expected_minutes } },
      pts:  { label: "PTS",  actual: ->(bs) { bs.points.to_f },            proj: ->(p) { p.proj_points } },
      reb:  { label: "REB",  actual: ->(bs) { bs.total_rebounds.to_f },    proj: ->(p) { p.proj_rebounds } },
      ast:  { label: "AST",  actual: ->(bs) { bs.assists.to_f },           proj: ->(p) { p.proj_assists } },
      threes: { label: "3PM", actual: ->(bs) { bs.three_point_field_goals.to_f }, proj: ->(p) { p.proj_threes } },
      usg:  { label: "USG%", actual: ->(bs) { bs.usage_pct },              proj: ->(p) { p.usage_pct } },
      rebp: { label: "REB%", actual: ->(bs) { bs.total_rebound_pct },      proj: ->(p) { p.rebound_pct } },
      astp: { label: "AST%", actual: ->(bs) { bs.assist_pct },             proj: ->(p) { p.assist_pct } }
    }

    boxes = {}

    stat_defs.each do |key, defn|
      errors = []
      abs_errors = []

      box_scores.each do |bs|
        next if bs.minutes_played.to_f < minutes_threshold

        proj = proj_by_date_player[[bs.game.date, bs.player_id]]
        next if proj.nil?

        a = defn[:actual].call(bs)
        p = defn[:proj].call(proj)
        next if p.nil?

        err = a.to_f - p.to_f
        errors << err
        abs_errors << err.abs
      end

      n = errors.size

      boxes[key] = {
        label: defn[:label],
        n: n,
        mae:  (n > 0 ? (abs_errors.sum / n.to_f) : nil),
        bias: (n > 0 ? (errors.sum / n.to_f)     : nil)
      }
    end

    boxes
  end


  def build_metric_boxes(box_scores, proj_by_player_id, minutes_threshold: 0)
    stat_defs = {
      min:  { label: "MIN",  actual: ->(bs) { bs.minutes_played.to_f },    proj: ->(p) { p.expected_minutes } },
      pts:  { label: "PTS",  actual: ->(bs) { bs.points.to_f },            proj: ->(p) { p.proj_points } },
      reb:  { label: "REB",  actual: ->(bs) { bs.total_rebounds.to_f },    proj: ->(p) { p.proj_rebounds } },
      ast:  { label: "AST",  actual: ->(bs) { bs.assists.to_f },           proj: ->(p) { p.proj_assists } },
      usg:  { label: "USG%", actual: ->(bs) { bs.usage_pct },              proj: ->(p) { p.usage_pct } },
      rebp: { label: "REB%", actual: ->(bs) { bs.total_rebound_pct },      proj: ->(p) { p.rebound_pct } },
      astp: { label: "AST%", actual: ->(bs) { bs.assist_pct },             proj: ->(p) { p.assist_pct } }
    }

    boxes = {}

    stat_defs.each do |key, defn|
      errors = []
      abs_errors = []

      box_scores.each do |bs|
        next if bs.minutes_played.to_f < minutes_threshold

        proj = proj_by_player_id[bs.player_id]
        next if proj.nil?

        a = defn[:actual].call(bs)
        p = defn[:proj].call(proj)

        next if p.nil?

        a = a.to_f
        p = p.to_f

        err = a - p
        errors << err
        abs_errors << err.abs
      end

      n = errors.size

      boxes[key] = {
        label: defn[:label],
        n: n,
        mae:  (n > 0 ? (abs_errors.sum / n.to_f) : nil),
        bias: (n > 0 ? (errors.sum / n.to_f)     : nil)
      }
    end

    boxes
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



end

