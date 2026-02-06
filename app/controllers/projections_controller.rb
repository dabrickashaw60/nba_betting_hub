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

    # -------------------------
    # Safe defaults
    # -------------------------
    @games             = []
    @selected_game     = nil

    @box_scores        = []
    @proj_by_player_id = {}

    @day_metric_boxes  = {}
    @metric_boxes      = {}

    @day_missing_projection_count = 0
    @day_missing_projection_players = []

    @guide_scope = params[:scope].presence || "day"
    @guide_metric_boxes = {}
    @guide_missing_projection_count = 0

    @selected_team_id = params[:team_id].presence

    # Team-split defaults (view expects these)
    @away_box_scores = []
    @home_box_scores = []
    @away_proj_by_player_id = {}
    @home_proj_by_player_id = {}
    @away_metric_boxes = {}
    @home_metric_boxes = {}
    @away_missing_projection_count = 0
    @home_missing_projection_count = 0
    @away_display_rows = []
    @home_display_rows = []

    return unless @season

    # -------------------------
    # Games for the date
    # -------------------------
    @games = Game.where(date: @date, season_id: @season.id)
                 .includes(:home_team, :visitor_team)
                 .order(:time)
                 .to_a

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
    today = Date.today
    range =
      case @guide_scope
      when "overall"
        (Game.where(season_id: @season.id).minimum(:date) || today)..today
      when "last3"
        (today - 2)..today
      when "last7"
        (today - 6)..today
      else
        @date..@date
      end

    guide_games = Game.where(season_id: @season.id, date: range)
                      .includes(:home_team, :visitor_team)
                      .to_a

    if guide_games.any?
      @guide_metric_boxes, @guide_missing_projection_count =
        build_metrics_for_games(guide_games, minutes_threshold: 0, missing_minutes_cutoff: 10)
    end

    # ------------------------------------------------------------
    # SELECTED GAME (team-separated + include proj-only rows in table)
    # ------------------------------------------------------------
    return unless params[:game_id].present? && @games.any?

    @selected_game = @games.find { |g| g.id == params[:game_id].to_i }
    return unless @selected_game

    home_id  = @selected_game.home_team_id
    away_id  = @selected_game.visitor_team_id
    team_ids = [home_id, away_id].compact

    # All box scores for game
    all_box_scores = BoxScore.where(game_id: @selected_game.id)
                             .includes(:player, :team)
                             .to_a

    @away_box_scores = all_box_scores.select { |bs| bs.team_id == away_id }
                                     .sort_by { |bs| -bs.minutes_played.to_f }

    @home_box_scores = all_box_scores.select { |bs| bs.team_id == home_id }
                                     .sort_by { |bs| -bs.minutes_played.to_f }

    # Projections for both teams
    projections = Projection.where(date: @date)
                            .where(team_id: team_ids)
                            .where(opponent_team_id: team_ids)
                            .includes(:player, :team)
                            .to_a

    all_proj_by_player_id = projections.index_by(&:player_id)

    @away_proj_by_player_id = projections.select { |p| p.team_id == away_id }.index_by(&:player_id)
    @home_proj_by_player_id = projections.select { |p| p.team_id == home_id }.index_by(&:player_id)

    # -------------------------
    # Proj-only rows (no box score row)
    # -------------------------
    away_box_player_ids = @away_box_scores.map(&:player_id).compact.to_set
    home_box_player_ids = @home_box_scores.map(&:player_id).compact.to_set

    away_proj_no_box = projections.select do |p|
      p.team_id == away_id && !away_box_player_ids.include?(p.player_id)
    end

    home_proj_no_box = projections.select do |p|
      p.team_id == home_id && !home_box_player_ids.include?(p.player_id)
    end

    # -------------------------
    # Build display rows (box rows + proj-only rows)
    # Each element: { type:, bs:, proj: }
    # -------------------------
    @away_display_rows =
      (@away_box_scores.map { |bs| { type: :box, bs: bs, proj: @away_proj_by_player_id[bs.player_id] } } +
       away_proj_no_box.map { |p|  { type: :proj_only, bs: nil, proj: p } })
        .sort_by do |r|
          r[:bs] ? -r[:bs].minutes_played.to_f : -r[:proj].expected_minutes.to_f
        end

    @home_display_rows =
      (@home_box_scores.map { |bs| { type: :box, bs: bs, proj: @home_proj_by_player_id[bs.player_id] } } +
       home_proj_no_box.map { |p|  { type: :proj_only, bs: nil, proj: p } })
        .sort_by do |r|
          r[:bs] ? -r[:bs].minutes_played.to_f : -r[:proj].expected_minutes.to_f
        end

    # -------------------------
    # Missing projections (box score exists, projection missing)
    # -------------------------
    minutes_cutoff = 10

    away_missing = @away_box_scores.select do |bs|
      bs.minutes_played.to_f >= minutes_cutoff && @away_proj_by_player_id[bs.player_id].nil?
    end

    home_missing = @home_box_scores.select do |bs|
      bs.minutes_played.to_f >= minutes_cutoff && @home_proj_by_player_id[bs.player_id].nil?
    end

    @away_missing_projection_count = away_missing.size
    @home_missing_projection_count = home_missing.size

    # -------------------------
    # Metric cards (per team)
    # NOTE: build_metric_boxes only uses rows where a projection exists,
    # so proj-only rows don't belong here (no actuals).
    # -------------------------
    @away_metric_boxes = build_metric_boxes(@away_box_scores, @away_proj_by_player_id, minutes_threshold: 0)
    @home_metric_boxes = build_metric_boxes(@home_box_scores, @home_proj_by_player_id, minutes_threshold: 0)

    # -------------------------
    # Backward compat (if anything still references these)
    # -------------------------
    @box_scores        = all_box_scores
    @proj_by_player_id = all_proj_by_player_id
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

