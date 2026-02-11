# app/services/projections/baseline_model.rb
require "zlib"
require "set"

module ::Projections
  class BaselineModel
    MODEL_VERSION = "baseline_v1".freeze

    TEAM_TOTAL_MINUTES = 240.0

    # DVP impact: rank 1..30 -> multiplier
    DVP_MIN_MULT = 0.8
    DVP_MAX_MULT = 1.2

    # Recent window
    WINDOW_GAMES = 8

    # Eligibility
    MIN_GAMES = 5
    MIN_AVG_MINUTES = 12.0

    # Deterministic micro-variance (small)
    VAR_POINTS   = 0.03
    VAR_REBOUNDS = 0.04
    VAR_ASSISTS  = 0.04
    VAR_THREES   = 0.05

    # Minutes tuning
    MINUTES_CLAMP_BAND = 2.0
    MINUTES_MAX = 38.0
    MINUTES_MIN = 0.0

    # Injury redistribution tuning (conservative)
    USG_BOOST_CAP = 3.0
    REB_BOOST_CAP = 2.0
    AST_BOOST_CAP = 2.0

    # How much of OUT minutes / rates are considered "transferable" vs "lost" (rotation tightening / uncertainty)
    OUT_MINUTES_TRANSFER = 0.75
    OUT_USAGE_TRANSFER   = 0.65
    OUT_REB_TRANSFER     = 0.60
    OUT_AST_TRANSFER     = 0.60

    # On/Off history tuning
    # NOTE: With your scraper, OUT players typically have NO BoxScore row at all.
    # So "out game" is detected primarily as "no row exists", not "0:00".
    ONOFF_LOOKBACK_GAMES = 25
    ONOFF_SAMPLE_MIN = 2
    ONOFF_SAMPLE_CAP = 8
    ONOFF_BLEND_MAX = 0.80
    ONOFF_BLEND_MIN = 0.0

    def initialize(date:)
      @date = date
      @season = Season.find_by(current: true)
      raise "No current season" unless @season
    end

    def run!
      # delete child rows first, then parent rows (FK-safe)
      runs_to_delete = ProjectionRun.where(date: @date, model_version: MODEL_VERSION).pluck(:id)
      Projection.where(date: @date, projection_run_id: runs_to_delete).delete_all
      ProjectionRun.where(id: runs_to_delete).delete_all

      run = ::ProjectionRun.find_or_initialize_by(date: @date, model_version: MODEL_VERSION)
      run.update!(
        status: :running,
        started_at: Time.current,
        finished_at: nil,
        notes: nil,
        projections_count: 0
      )

      todays_games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
      team_ids = todays_games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq
      return mark_success(run) if team_ids.blank?

      eligible_player_ids = eligible_players_for(team_ids)

      # IMPORTANT: use to_a so we can group_by team and avoid find_each (find_each ignores ordering and batches)
      players = Player.where(id: eligible_player_ids).includes(:team, :health).to_a

      puts "[BASELINE] Eligible players (>#{MIN_AVG_MINUTES} min avg, >=#{MIN_GAMES} games, not Out): #{players.size}"

      injury_map_by_team = build_injury_adjustments(team_ids)

      count = 0
      players_by_team = players.group_by(&:team_id)

      players_by_team.each do |team_id, team_players|
        # Determine opponent for the team from todays_games
        game = todays_games.detect { |g| g.home_team_id == team_id || g.visitor_team_id == team_id }
        next unless game

        opp_team = (game.home_team_id == team_id) ? game.visitor_team : game.home_team
        next unless opp_team

        # 1) Build per-player inputs + pre-normalized minutes
        inputs_by_pid = {}
        explainer_by_pid = {}
        pre_minutes_by_pid = {}
        adj_pcts_by_pid = {}

        team_injury = injury_map_by_team[team_id] || {}

        team_players.each do |player|
          explainer = Projections::Explainer.new

          inputs = gather_inputs(player, opp_team)
          next if inputs.blank?

          explainer.add(
            step: "Inputs",
            detail: "Recent #{WINDOW_GAMES} game baselines",
            data: {
              position: inputs[:position],
              base_minutes: inputs[:minutes].round(2),
              ppm_points: inputs[:rates][:points_per_min].round(4),
              ppm_rebounds: inputs[:rates][:rebounds_per_min].round(4),
              ppm_assists: inputs[:rates][:assists_per_min].round(4),
              ppm_threes: inputs[:rates][:threes_per_min].round(4),
              base_usg: inputs[:pcts][:usage_pct].round(2),
              base_reb_pct: inputs[:pcts][:rebound_pct].round(2),
              base_ast_pct: inputs[:pcts][:assist_pct].round(2)
            }
          )

          deltas = team_injury[player.id] || {}

          raw_minutes_delta = deltas.fetch(:minutes_delta, 0.0)
          pre_minutes = clamp_minutes(inputs[:minutes] + raw_minutes_delta)

          if raw_minutes_delta.to_f != 0.0
            explainer.add(
              step: "Injury Minutes (240-normalized)",
              detail: "Team minutes redistribution constrained to 240 total (delta phase)",
              deltas: { minutes_delta_raw: raw_minutes_delta.round(2) },
              data: {
                minutes_before: inputs[:minutes].round(2),
                minutes_after_pre_norm: pre_minutes.round(2),
                team_total_minutes: TEAM_TOTAL_MINUTES
              }
            )
          end

          base_usg = inputs[:pcts][:usage_pct]
          base_reb = inputs[:pcts][:rebound_pct]
          base_ast = inputs[:pcts][:assist_pct]

          adj_usg = clamp_pct(base_usg + deltas.fetch(:usage_delta, 0.0), base_usg, USG_BOOST_CAP)
          adj_reb = clamp_pct(base_reb + deltas.fetch(:rebound_delta, 0.0), base_reb, REB_BOOST_CAP)
          adj_ast = clamp_pct(base_ast + deltas.fetch(:assist_delta, 0.0), base_ast, AST_BOOST_CAP)

          if deltas.present?
            explainer.add(
              step: "Injury Rates",
              detail: "Usage/Reb/Ast % deltas applied and capped",
              deltas: {
                usage_delta: deltas.fetch(:usage_delta, 0.0).round(2),
                rebound_delta: deltas.fetch(:rebound_delta, 0.0).round(2),
                assist_delta: deltas.fetch(:assist_delta, 0.0).round(2)
              },
              data: {
                usg_before: base_usg.round(2),
                usg_after: adj_usg.round(2),
                reb_before: base_reb.round(2),
                reb_after: adj_reb.round(2),
                ast_before: base_ast.round(2),
                ast_after: adj_ast.round(2),
                caps: { usg: USG_BOOST_CAP, reb: REB_BOOST_CAP, ast: AST_BOOST_CAP }
              }
            )
          end

          inputs_by_pid[player.id] = inputs
          explainer_by_pid[player.id] = explainer
          pre_minutes_by_pid[player.id] = pre_minutes
          adj_pcts_by_pid[player.id] = { usage_pct: adj_usg, rebound_pct: adj_reb, assist_pct: adj_ast }
        rescue => e
          Rails.logger.warn "[::Projections::BaselineModel] #{player&.name || 'player'} inputs failed: #{e.message}"
          next
        end

        next if inputs_by_pid.blank?

        # ------------------------------------------------------------
        # 2) Rotation pruning + bench dilution control (competitive-game assumption)
        #
        # Goal:
        # - Keep true rotation bodies
        # - Drop pure “garbage-time” guys (sub-10 minute profiles)
        # - Compress minutes away from deep bench so starters aren’t taxed down
        # ------------------------------------------------------------
        # Always keep at least N bodies (to avoid weird short-handed slates)
        min_rotation_bodies = 9

        # Sort by pre minutes (already includes injury deltas)
        ordered_pids = pre_minutes_by_pid.sort_by { |_pid, m| -m.to_f }.map(&:first)

        keep = Set.new

        # 2a) Always keep top N by pre-minutes
        ordered_pids.first(min_rotation_bodies).each { |pid| keep << pid }

        # 2b) Keep anyone with “real rotation” recent minutes
        inputs_by_pid.each do |pid, inputs|
          mp = (inputs[:minutes_profile] || {})
          last5  = mp[:last5_avg].to_f
          season = mp[:season_avg].to_f
          pre_m  = pre_minutes_by_pid[pid].to_f

          # Rotation signal rules (tunable):
          # - last5 >= 10 OR season >= 12 OR pre >= 12 => keep
          # This knocks out the “played only in blowouts” guys without needing blowout logic.
          if last5 >= 10.0 || season >= 12.0 || pre_m >= 12.0
            keep << pid
          end
        end

        # Apply keep set (drop others)
        drop_pids = inputs_by_pid.keys - keep.to_a
        drop_pids.each do |pid|
          inputs_by_pid.delete(pid)
          explainer_by_pid.delete(pid)
          pre_minutes_by_pid.delete(pid)
          adj_pcts_by_pid.delete(pid)
        end

        next if inputs_by_pid.blank?

        # 2c) Bench decay to prevent “14-man equalization”
        # After the top 8-ish bodies, taper pre-minutes down so normalization
        # doesn’t steal minutes from starters to fund deep bench.
        #
        # This is NOT blowout logic — it is “competitive rotation compression.”
        ordered_pids = pre_minutes_by_pid.sort_by { |_pid, m| -m.to_f }.map(&:first)

        ordered_pids.each_with_index do |pid, idx|
          m = pre_minutes_by_pid[pid].to_f
          mult =
            if idx <= 7
              1.00
            elsif idx <= 9
              0.85
            elsif idx <= 11
              0.70
            else
              0.55
            end

          new_m = clamp_minutes(m * mult)

          if mult < 1.0
            ex = explainer_by_pid[pid]
            ex&.add(
              step: "Rotation Compression",
              detail: "Competitive-game bench taper to prevent deep bench dilution",
              data: { rank_by_minutes: idx + 1, pre_minutes_before: m.round(2), multiplier: mult, pre_minutes_after: new_m.round(2) }
            )
          end

          pre_minutes_by_pid[pid] = new_m
        end

        # ------------------------------------------------------------
        # 3) Build floors (starter protection)
        #
        # Your old floors only protected true 33–35 MPG stars.
        # This expands protection to “normal starters” too (Heat example).
        # ------------------------------------------------------------
        floors_by_pid = {}

        # Identify “starter-like” group as top 5 by a blend of last5 + season-like minutes
        starter_candidates =
          inputs_by_pid.map do |pid, inputs|
            mp = (inputs[:minutes_profile] || {})
            last5  = mp[:last5_avg].to_f
            season = mp[:season_avg].to_f
            score = (0.65 * last5) + (0.35 * season)
            [pid, score, last5, season]
          end
          .sort_by { |(_pid, score, _l5, _s)| -score }

        starter_pids = starter_candidates.first(5).map(&:first).to_set

        inputs_by_pid.each do |pid, inputs|
          mp = (inputs[:minutes_profile] || {})
          last5  = mp[:last5_avg].to_f
          season = mp[:season_avg].to_f

          floor = 0.0

          # Expanded starter protection:
          # - For the top 5 “starter-like” players, floor near last5-2 (but not below 20)
          if starter_pids.include?(pid)
            floor = [last5 - 2.0, season - 1.0, 20.0].max
          end

          # Keep your stricter star floors as an override upward
          if last5 >= 35.0 && season >= 35.0
            floor = [floor, 35.0].max
          elsif last5 >= 33.0 && season >= 33.0
            floor = [floor, 33.0].max
          elsif last5 >= 31.0 && season >= 32.0
            floor = [floor, 31.0].max
          end

          floor = clamp_minutes(floor)

          if floor > 0.0
            floors_by_pid[pid] = floor
          end

          ex = explainer_by_pid[pid]
          ex&.add(
            step: "Minute Floors",
            detail: "Starter/star protection floors based on last5 + season-like minutes",
            data: {
              is_starter_like: starter_pids.include?(pid),
              last5_avg: last5.round(2),
              season_like_avg: season.round(2),
              floor_minutes: (floor > 0 ? floor.round(2) : nil)
            }
          )
        end

        # ------------------------------------------------------------
        # 4) Normalize team minutes to 240 (WITH floors)
        # ------------------------------------------------------------
        pre_total = pre_minutes_by_pid.values.sum.to_f
        norm_minutes_by_pid =
          normalize_minutes_to_team_total(
            pre_minutes_by_pid,
            target_total: TEAM_TOTAL_MINUTES,
            floors_by_pid: floors_by_pid
          )
        post_total = norm_minutes_by_pid.values.sum.to_f
        norm_factor = pre_total > 0 ? (TEAM_TOTAL_MINUTES / pre_total) : 1.0

        # add a normalization explainer step per player
        norm_minutes_by_pid.each do |pid, norm_mins|
          ex = explainer_by_pid[pid]
          next unless ex

          ex.add(
            step: "Team Minutes Normalization",
            detail: "Scaled team minutes to #{TEAM_TOTAL_MINUTES} total (with floors)",
            data: {
              team_pre_total: pre_total.round(2),
              team_post_total: post_total.round(2),
              naive_normalization_factor: norm_factor.round(4),
              minutes_pre_norm: pre_minutes_by_pid[pid].to_f.round(2),
              minutes_post_norm: norm_mins.to_f.round(2),
              floor_applied: (floors_by_pid[pid].present? ? floors_by_pid[pid].to_f.round(2) : nil)
            }
          )
        end

        # ------------------------------------------------------------
        # 5) Project stats + save rows
        # ------------------------------------------------------------
        inputs_by_pid.each do |pid, inputs|
          player = inputs[:player]
          explainer = explainer_by_pid[pid]
          norm_minutes = norm_minutes_by_pid.fetch(pid, 0.0).to_f
          pcts = adj_pcts_by_pid[pid] || inputs[:pcts]

          inputs_for_projection = inputs.merge(
            minutes: clamp_minutes(norm_minutes),
            pcts: pcts
          )

          outputs = project_stats(inputs_for_projection, explainer: explainer)

          projection = Projection.find_or_initialize_by(date: @date, player_id: player.id)
          projection.assign_attributes(
            projection_run_id: run.id,
            team_id: team_id,
            opponent_team_id: opp_team.id,
            position: inputs[:position],

            expected_minutes: inputs_for_projection[:minutes],
            usage_pct: pcts[:usage_pct],
            rebound_pct: pcts[:rebound_pct],
            assist_pct: pcts[:assist_pct],

            proj_points: outputs[:points],
            proj_rebounds: outputs[:rebounds],
            proj_assists: outputs[:assists],
            proj_threes: outputs[:threes],
            proj_pa: outputs[:points] + outputs[:assists],
            proj_pr: outputs[:points] + outputs[:rebounds],
            proj_ra: outputs[:rebounds] + outputs[:assists],
            proj_pra: outputs[:points] + outputs[:rebounds] + outputs[:assists],
            explain: explainer&.steps&.to_json
          )
          projection.save!
          count += 1
        rescue => e
          Rails.logger.warn "[::Projections::BaselineModel] #{player&.name || 'player'} save failed: #{e.message}"
          next
        end
      end

      run.update!(projections_count: count)
      mark_success(run)
    rescue => e
      run&.update!(status: :error, finished_at: Time.current, notes: e.message)
      raise
    end

    def debug_player!(player_id)
      todays_games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
      player = Player.includes(:team).find(player_id)
      opp = next_opponent_for(player, todays_games)

      puts "No opponent found for #{player.name} on #{@date}" and return unless opp

      inputs = gather_inputs(player, opp)
      puts "Inputs blank for #{player.name}" and return if inputs.blank?

      puts "================ DEBUG PLAYER ================"
      puts "Player: #{player.name} (#{player.position}) Team: #{player.team&.abbreviation} Opp: #{opp.abbreviation}"
      puts "Expected minutes: #{inputs[:minutes].to_f.round(2)}"
      puts "Rates: #{inputs[:rates].inspect}"
      puts "=============================================="

      outputs = project_stats(inputs)
      puts "Projected: PTS=#{outputs[:points]} REB=#{outputs[:rebounds]} AST=#{outputs[:assists]}"
      outputs
    end

    private

    def mark_success(run)
      run.update!(status: :success, finished_at: Time.current)
      run
    end

    def eligible_players_for(team_ids)
      recent_date_cutoff = (@date - 30.days).to_date
      last14_cutoff      = (@date - 14.days).to_date

      recent_game_ids = Game
        .where(season_id: @season.id)
        .where("date <= ?", @date)
        .where("home_team_id IN (?) OR visitor_team_id IN (?)", team_ids, team_ids)
        .order(date: :desc)
        .limit(10 * team_ids.size)
        .pluck(:id)

      recent_game_ids_sql = recent_game_ids.any? ? recent_game_ids.join(",") : "NULL"

      minutes_seconds_sql = %Q(
        (
          (CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", 1) AS UNSIGNED) * 60) +
          CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", -1) AS UNSIGNED)
        )
      ).squish

      Player
        .joins(box_scores: :game)
        .where(players: { team_id: team_ids })
        .where(games: { season_id: @season.id })
        .where("games.date <= ?", @date)
        .where.not(box_scores: { minutes_played: [nil, "", "0:00"] })
        .joins("LEFT JOIN healths ON healths.player_id = players.id")
        .where('COALESCE(healths.status, "Healthy") <> "Out"')
        .group("players.id")
        .having(<<~SQL.squish)
          COUNT(box_scores.id) >= #{MIN_GAMES}
          AND (
            MAX(games.date) >= '#{recent_date_cutoff}'
            OR SUM(CASE WHEN box_scores.game_id IN (#{recent_game_ids_sql}) THEN 1 ELSE 0 END) >= 1
          )
          AND (
            AVG(#{minutes_seconds_sql}) >= #{(MIN_AVG_MINUTES * 60).to_i}
            OR SUM(
              CASE
                WHEN games.date >= '#{last14_cutoff}'
                AND #{minutes_seconds_sql} >= #{(10.0 * 60).to_i}
                THEN 1 ELSE 0
              END
            ) >= 2
          )
        SQL
        .pluck(:id)
    end


    def next_opponent_for(player, todays_games)
      g = todays_games.detect { |game| game.home_team_id == player.team_id || game.visitor_team_id == player.team_id }
      return nil unless g
      g.home_team_id == player.team_id ? g.visitor_team : g.home_team
    end

    # -------------------------
    # Inputs: per-minute baselines
    # -------------------------
    def gather_inputs(player, opponent)
      bs_rel = player.box_scores
                    .joins(:game)
                    .where(games: { season_id: @season.id })
                    .where("games.date <= ?", @date)
                    .where.not(minutes_played: [nil, "", "0:00"])
                    .where.not(points: nil)
                    .order("games.date DESC")

      # Use a wider set for "season-like" minutes baseline, but still recent-ish
      # so we don't pull in early-season role noise forever.
      bs_for_minutes = bs_rel.limit(30)

      last5_rows = bs_for_minutes.limit(5).pluck(:minutes_played)
      all_rows   = bs_for_minutes.pluck(:minutes_played)

      last5_mins = last5_rows.map { |m| minutes_to_float(m) }.select { |v| v > 0.0 }
      all_mins   = all_rows.map { |m| minutes_to_float(m) }.select { |v| v > 0.0 }

      return nil if all_mins.blank?
      return nil if all_mins.size < MIN_GAMES

      last5_avg  = (last5_mins.any? ? (last5_mins.sum / last5_mins.size.to_f) : 0.0)
      season_avg = (all_mins.sum / all_mins.size.to_f)

      # Blend: lean on last5, but anchor with season_avg
      # If we have fewer than 3 games in last5 sample, lean more on season.
      last5_weight =
        if last5_mins.size >= 4
          0.70
        elsif last5_mins.size == 3
          0.60
        elsif last5_mins.size == 2
          0.45
        else
          0.25
        end

      blended_minutes = (last5_avg * last5_weight) + (season_avg * (1.0 - last5_weight))

      # Keep your clamp band concept, but center around season_avg to protect stars,
      # while still allowing last5 to pull them up/down modestly.
      lower = [season_avg - 3.0, 0.0].max
      upper = season_avg + 3.0

      expected_minutes = [[blended_minutes, lower].max, upper].min
      expected_minutes = clamp_minutes(expected_minutes)

      # Now pull the stat columns for the WINDOW used for rates/pcts
      bs_rates = bs_rel.limit(WINDOW_GAMES)

      cols = BoxScore.column_names
      rebound_count_col =
        if cols.include?("total_rebounds")
          :total_rebounds
        elsif cols.include?("rebounds")
          :rebounds
        else
          nil
        end

      has_usg = cols.include?("usage_pct")
      has_ast_pct = cols.include?("assist_pct")
      has_trb_pct = cols.include?("total_rebound_pct")

      if rebound_count_col
        rows = bs_rates.pluck(
          :minutes_played, :points, rebound_count_col, :assists, :three_point_field_goals,
          (has_usg ? :usage_pct : nil),
          (has_ast_pct ? :assist_pct : nil),
          (has_trb_pct ? :total_rebound_pct : nil)
        )
      else
        o_col = cols.include?("offensive_rebounds") ? :offensive_rebounds : nil
        d_col = cols.include?("defensive_rebounds") ? :defensive_rebounds : nil
        rows = bs_rates.pluck(
          :minutes_played, :points, o_col, d_col, :assists, :three_point_field_goals,
          (has_usg ? :usage_pct : nil),
          (has_ast_pct ? :assist_pct : nil),
          (has_trb_pct ? :total_rebound_pct : nil)
        )
      end

      return nil if rows.blank?

      totals = accumulate_totals(rows, rebound_count_col: rebound_count_col)
      return nil if totals[:games] < [MIN_GAMES, 3].min
      return nil if totals[:total_minutes] <= 0.0

      ppm_points   = totals[:points].to_f / totals[:total_minutes]
      ppm_rebounds = totals[:rebounds].to_f / totals[:total_minutes]
      ppm_assists  = totals[:assists].to_f / totals[:total_minutes]
      ppm_threes   = totals[:threes].to_f / totals[:total_minutes]

      base_usg = totals[:usage_pct_vals].any? ? (totals[:usage_pct_vals].sum / totals[:usage_pct_vals].size) : 0.0
      base_ast = totals[:assist_pct_vals].any? ? (totals[:assist_pct_vals].sum / totals[:assist_pct_vals].size) : 0.0
      base_trb = totals[:trb_pct_vals].any? ? (totals[:trb_pct_vals].sum / totals[:trb_pct_vals].size) : 0.0

      {
        player: player,
        opponent: opponent,
        position: player.position,
        minutes: expected_minutes,
        minutes_profile: {
          last5_avg: last5_avg,
          season_avg: season_avg,
          last5_weight: last5_weight
        },
        rates: {
          points_per_min: ppm_points,
          rebounds_per_min: ppm_rebounds,
          assists_per_min: ppm_assists,
          threes_per_min: ppm_threes
        },
        pcts: {
          usage_pct: base_usg,
          assist_pct: base_ast,
          rebound_pct: base_trb
        }
      }
    end




    def accumulate_totals(rows, rebound_count_col:)
      total_minutes = 0.0
      points = 0.0
      rebounds = 0.0
      assists = 0.0
      threes = 0.0
      games = 0
      minutes_list = []

      usage_pct_vals = []
      assist_pct_vals = []
      trb_pct_vals = []

      rows.each do |row|
        mins_str = row[0]
        pts = row[1]

        if rebound_count_col
          reb     = row[2]
          ast     = row[3]
          th3     = row[4]
          usg     = row[5]
          ast_pct = row[6]
          trb_pct = row[7]
        else
          oreb    = row[2]
          dreb    = row[3]
          reb     = oreb.to_i + dreb.to_i
          ast     = row[4]
          th3     = row[5]
          usg     = row[6]
          ast_pct = row[7]
          trb_pct = row[8]
        end

        mins = minutes_to_float(mins_str)
        next if mins <= 0.0

        minutes_list << mins
        total_minutes += mins
        points += pts.to_f
        rebounds += reb.to_f
        assists += ast.to_f
        threes += th3.to_f
        games += 1

        usage_pct_vals << usg.to_f if usg.present?
        assist_pct_vals << ast_pct.to_f if ast_pct.present?
        trb_pct_vals << trb_pct.to_f if trb_pct.present?
      end

      {
        total_minutes: total_minutes,
        points: points,
        rebounds: rebounds,
        assists: assists,
        threes: threes,
        games: games,
        minutes_list: minutes_list,
        usage_pct_vals: usage_pct_vals,
        assist_pct_vals: assist_pct_vals,
        trb_pct_vals: trb_pct_vals
      }
    end

    def minutes_to_float(value)
      return 0.0 if value.blank?
      return value.to_f if value.is_a?(Numeric)
      return value.to_f unless value.include?(":")

      m, s = value.split(":").map(&:to_i)
      m + (s / 60.0)
    rescue
      0.0
    end

    def projected_minutes_from_recent(minutes_list, last5_avg: nil, season_avg: nil)
      return 0.0 if minutes_list.blank?

      n = minutes_list.size
      weights = n.downto(1).to_a
      weighted = minutes_list.zip(weights).sum { |m, w| m.to_f * w } / weights.sum.to_f

      avg_window = minutes_list.sum.to_f / n

      l5 = last5_avg.to_f
      sea = season_avg.to_f

      # Blend target:
      # - last 5 is most important
      # - weighted window next
      # - season-like keeps stars from being “taxed” too hard
      # Feel free to tweak weights later.
      blended =
        (0.55 * (l5 > 0 ? l5 : avg_window)) +
        (0.25 * weighted) +
        (0.20 * (sea > 0 ? sea : avg_window))

      # Clamp around the blended value (instead of the window avg)
      lower = [blended - MINUTES_CLAMP_BAND, 0.0].max
      upper = blended + MINUTES_CLAMP_BAND

      out = [[blended, lower].max, upper].min
      clamp_minutes(out)
    end


    def clamp_minutes(mins)
      mins = mins.to_f
      mins = MINUTES_MIN if mins < MINUTES_MIN
      mins = MINUTES_MAX if mins > MINUTES_MAX
      mins
    end

    def clamp_pct(value, baseline, cap)
      v = value.to_f
      b = baseline.to_f
      lo = b - cap
      hi = b + cap
      [[v, lo].max, hi].min
    end

    # -------------------------
    # Injury adjustments
    # - Minutes: team-level redistribution normalized to 240
    # - Rates: blend redistribution (pool-based) with on/off history
    # IMPORTANT: baselines are computed from TEAM's last WINDOW_GAMES (rotation context),
    # not each player's last WINDOW_GAMES appearances.
    # -------------------------
    def build_injury_adjustments(team_ids)
      result = {}

      team_players = Player.includes(:health).where(team_id: team_ids).to_a
      players_by_team = team_players.group_by(&:team_id)

      cols = BoxScore.column_names
      has_usg     = cols.include?("usage_pct")
      has_ast_pct = cols.include?("assist_pct")
      has_trb_pct = cols.include?("total_rebound_pct")

      Team.where(id: team_ids).find_each do |team|
        roster = players_by_team[team.id] || []
        if roster.blank?
          result[team.id] = {}
          next
        end

        # TEAM recent games (rotation context)
        recent_games = Game.where(season_id: @season.id)
                          .where("home_team_id = ? OR visitor_team_id = ?", team.id, team.id)
                          .order(date: :desc)
                          .limit(WINDOW_GAMES)
                          .pluck(:id)

        if recent_games.blank?
          result[team.id] = {}
          next
        end

        roster_ids = roster.map(&:id)

        # Build baselines from TEAM recent games only
        pluck_cols = [:player_id, :minutes_played]
        pluck_cols << :usage_pct if has_usg
        pluck_cols << :assist_pct if has_ast_pct
        pluck_cols << :total_rebound_pct if has_trb_pct

        bs = BoxScore.where(game_id: recent_games, player_id: roster_ids)
                    .where.not(minutes_played: [nil, "", "0:00"])
                    .pluck(*pluck_cols)

        mins_map = Hash.new { |h, k| h[k] = [] }
        usg_map  = Hash.new { |h, k| h[k] = [] }
        ast_map  = Hash.new { |h, k| h[k] = [] }
        trb_map  = Hash.new { |h, k| h[k] = [] }

        bs.each do |row|
          pid = row[0]
          mp  = row[1]
          idx = 2

          usg  = has_usg     ? row[idx].tap { idx += 1 } : nil
          astp = has_ast_pct ? row[idx].tap { idx += 1 } : nil
          trbp = has_trb_pct ? row[idx].tap { idx += 1 } : nil

          m = minutes_to_float(mp)
          next if m <= 0.0

          mins_map[pid] << m
          usg_map[pid]  << usg.to_f  if usg.present?
          ast_map[pid]  << astp.to_f if astp.present?
          trb_map[pid]  << trbp.to_f if trbp.present?
        end

        roster_baseline = {}
        roster_ids.each do |pid|
          mins = mins_map[pid]
          roster_baseline[pid] = {
            minutes:      (mins.any? ? (mins.sum / mins.size) : 0.0),
            usage_pct:    (usg_map[pid].any? ? (usg_map[pid].sum / usg_map[pid].size) : 0.0),
            assist_pct:   (ast_map[pid].any? ? (ast_map[pid].sum / ast_map[pid].size) : 0.0),
            rebound_pct:  (trb_map[pid].any? ? (trb_map[pid].sum / trb_map[pid].size) : 0.0)
          }
        end

        # Active/Out based on health
        out_players_all = roster.select { |p| p.health&.status.to_s == "Out" }
        active_players  = roster.reject { |p| p.health&.status.to_s == "Out" }

        if out_players_all.blank? || active_players.blank?
          result[team.id] = {}
          next
        end

        # IMPORTANT: only count OUT players who actually appeared in TEAM recent window
        out_players = out_players_all.select do |p|
          roster_baseline[p.id][:minutes].to_f > 0.0
        end

        if out_players.blank?
          result[team.id] = {}
          next
        end

        # Minutes deltas (team constrained to 240)
        minute_deltas = build_team_minutes_deltas(team, roster, out_players, active_players, roster_baseline)

        # Rate deltas (pool-based)
        redistribution_rates = build_redistribution_rate_deltas(team, roster, out_players, active_players, roster_baseline)

        # On/Off rate deltas (rates only)
        onoff = build_onoff_deltas(team, active_players, out_players, has_usg: has_usg, has_ast_pct: has_ast_pct, has_trb_pct: has_trb_pct)

        deltas_for_team = Hash.new do |h, k|
          h[k] = { minutes_delta: 0.0, usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0 }
        end

        active_players.each do |p|
          ro = redistribution_rates[p.id] || {}
          oo = onoff[p.id] || {}

          w = oo.fetch(:weight, 0.0)
          w = ONOFF_BLEND_MAX if w > ONOFF_BLEND_MAX
          w = ONOFF_BLEND_MIN if w < ONOFF_BLEND_MIN

          deltas_for_team[p.id][:minutes_delta] = minute_deltas.fetch(p.id, 0.0)

          deltas_for_team[p.id][:usage_delta] =
            (oo.fetch(:usage_delta, 0.0) * w) + (ro.fetch(:usage_delta, 0.0) * (1.0 - w))

          deltas_for_team[p.id][:rebound_delta] =
            (oo.fetch(:rebound_delta, 0.0) * w) + (ro.fetch(:rebound_delta, 0.0) * (1.0 - w))

          deltas_for_team[p.id][:assist_delta] =
            (oo.fetch(:assist_delta, 0.0) * w) + (ro.fetch(:assist_delta, 0.0) * (1.0 - w))
        end

        result[team.id] = deltas_for_team
      end

      result
    end


    # -------------------------
    # Minutes: team-level redistribution constrained to 240
    # Adds baseline-relative cap to prevent instant jumps to MINUTES_MAX.
    # -------------------------
    def build_team_minutes_deltas(team, roster, out_players, active_players, baseline_map)
      # 1) Start from roster baseline minutes (already team-window baselines)
      raw_minutes = {}
      roster.each do |p|
        raw_minutes[p.id] = (baseline_map[p.id] || {})[:minutes].to_f
      end

      sum_raw = raw_minutes.values.sum.to_f
      return {} if sum_raw <= 0.0

      # Scale roster baseline to 240
      scale = TEAM_TOTAL_MINUTES / sum_raw
      base_scaled = raw_minutes.transform_values { |m| clamp_minutes(m * scale) }

      # After clamp, re-normalize to 240 again
      base_scaled = renormalize_minutes(base_scaled, target_total: TEAM_TOTAL_MINUTES)

      out_ids    = out_players.map(&:id)
      active_ids = active_players.map(&:id)

      out_sum = out_ids.sum { |pid| base_scaled[pid].to_f }
      return {} if out_sum <= 0.0

      # 2) Decide how many OUT minutes are transferable
      transferable = out_sum * OUT_MINUTES_TRANSFER
      locked_out   = out_sum - transferable
      target_active_total = TEAM_TOTAL_MINUTES - locked_out

      # Baseline active minutes
      active_base = {}
      active_ids.each { |pid| active_base[pid] = base_scaled[pid].to_f }

      base_active_sum = active_base.values.sum.to_f
      return {} if base_active_sum <= 0.0

      # 3) Distribute transferable minutes to actives using position-aware pools
      out_by_group    = out_players.group_by { |p| minutes_group_for(p.position) }
      active_by_group = active_players.group_by { |p| minutes_group_for(p.position) }

      weight_for = lambda do |pid|
        m = active_base[pid].to_f
        usg = (baseline_map[pid] || {})[:usage_pct].to_f
        w = (m > 0 ? m : 8.0)
        w *= (1.0 + (usg / 100.0) * 0.35)
        [w, 5.0].max
      end

      added = Hash.new(0.0)

      distribute_pool = lambda do |pool_minutes, receiver_players|
        return if pool_minutes.to_f <= 0.0 || receiver_players.blank?

        weights = {}
        receiver_players.each { |p| weights[p.id] = weight_for.call(p.id) }
        wsum = weights.values.sum.to_f
        return if wsum <= 0.0

        weights.each do |pid, w|
          added[pid] += pool_minutes.to_f * (w / wsum)
        end
      end

      remaining_pool = transferable.to_f

      %w[G F C OTHER].each do |grp|
        outs = out_by_group[grp] || []
        next if outs.blank?

        grp_out_sum = outs.sum { |p| base_scaled[p.id].to_f }
        grp_pool = grp_out_sum * OUT_MINUTES_TRANSFER
        next if grp_pool <= 0.0

        receivers = active_by_group[grp] || []
        distribute_pool.call(grp_pool, receivers)
        remaining_pool -= grp_pool
      end

      distribute_pool.call(remaining_pool, active_players) if remaining_pool > 0.0

      # 4) Build new active minutes
      new_active = {}
      active_ids.each do |pid|
        new_active[pid] = active_base[pid].to_f + added[pid].to_f
      end

      # First renormalize to target
      new_active = renormalize_minutes(new_active, target_total: target_active_total)

      # 4b) Baseline-relative cap pass (prevents snap-to-38)
      # You can tune this: +3.5 is a good starting point.
      per_player_boost_cap = 3.5

      overflow = 0.0
      capped = {}

      active_ids.each do |pid|
        base_m = active_base[pid].to_f
        cap_m  = [base_m + per_player_boost_cap, MINUTES_MAX].min
        cap_m  = [cap_m, MINUTES_MIN].max

        if new_active[pid].to_f > cap_m
          overflow += (new_active[pid].to_f - cap_m)
          capped[pid] = cap_m
        else
          capped[pid] = new_active[pid].to_f
        end
      end

      # Redistribute overflow to players not at cap (weighted)
      if overflow > 0.0
        receivers = active_ids.select { |pid| capped[pid].to_f < [active_base[pid].to_f + per_player_boost_cap, MINUTES_MAX].min - 0.001 }
        if receivers.any?
          weights = {}
          receivers.each { |pid| weights[pid] = weight_for.call(pid) }
          wsum = weights.values.sum.to_f

          if wsum > 0.0
            weights.each do |pid, w|
              capped[pid] += overflow * (w / wsum)
            end
          end
        end
      end

      # Final clamp + re-normalize
      new_active = clamp_and_renormalize_minutes(capped, target_total: target_active_total)

      # 5) Return deltas vs baseline active minutes
      deltas = {}
      active_ids.each do |pid|
        deltas[pid] = new_active[pid].to_f - active_base[pid].to_f
      end

      deltas
    end


    def minutes_group_for(pos)
      case pos
      when "PG", "SG" then "G"
      when "SF", "PF" then "F"
      when "C"        then "C"
      else "OTHER"
      end
    end

    def renormalize_minutes(minutes_hash, target_total:)
      total = minutes_hash.values.sum.to_f
      return minutes_hash if total <= 0.0
      factor = target_total.to_f / total
      minutes_hash.transform_values { |m| m.to_f * factor }
    end

    def clamp_and_renormalize_minutes(minutes_hash, target_total:)
      h = minutes_hash.dup

      3.times do
        # clamp
        h.each do |pid, m|
          h[pid] = clamp_minutes(m)
        end

        total = h.values.sum.to_f
        break if total <= 0.0

        diff = target_total.to_f - total
        break if diff.abs < 0.01

        if diff > 0
          # add minutes only to players not already at max
          elig = h.select { |_pid, m| m < MINUTES_MAX - 0.001 }
          elig_total = elig.values.sum.to_f
          break if elig_total <= 0.0

          elig.each do |pid, m|
            share = (m.to_f / elig_total)
            h[pid] = [h[pid] + diff * share, MINUTES_MAX].min
          end
        else
          # remove minutes only from players above min
          diff_abs = diff.abs
          elig = h.select { |_pid, m| m > MINUTES_MIN + 0.001 }
          elig_total = elig.values.sum.to_f
          break if elig_total <= 0.0

          elig.each do |pid, m|
            share = (m.to_f / elig_total)
            h[pid] = [h[pid] - diff_abs * share, MINUTES_MIN].max
          end
        end

        # re-normalize softly toward target
        h = renormalize_minutes(h, target_total: target_total)
      end

      h
    end

    # -------------------------
    # Rates redistribution (pool-based) - no minutes here
    # -------------------------
    def build_redistribution_rate_deltas(team, roster, out_players, active_players, baseline_map)
      out_ids = out_players.map(&:id)
      active_ids = active_players.map(&:id)
      return {} if out_ids.blank? || active_ids.blank?

      avg_usg  = ->(pid) { (baseline_map[pid] || {})[:usage_pct].to_f }
      avg_ast  = ->(pid) { (baseline_map[pid] || {})[:assist_pct].to_f }
      avg_trb  = ->(pid) { (baseline_map[pid] || {})[:rebound_pct].to_f }
      avg_mins = ->(pid) { (baseline_map[pid] || {})[:minutes].to_f }

      pool_usg = out_players.sum { |p| avg_usg.call(p.id) } * OUT_USAGE_TRANSFER
      pool_ast = out_players.sum { |p| avg_ast.call(p.id) } * OUT_AST_TRANSFER
      pool_trb = out_players.sum { |p| avg_trb.call(p.id) } * OUT_REB_TRANSFER

      active_by_group = active_players.group_by { |p| minutes_group_for(p.position) }
      out_by_group    = out_players.group_by { |p| minutes_group_for(p.position) }

      deltas = Hash.new { |h, k| h[k] = { usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0 } }

      distribute = lambda do |pool, receiver_players|
        return {} if pool.to_f <= 0.0 || receiver_players.blank?

        weights = {}
        receiver_players.each do |p|
          m = avg_mins.call(p.id)
          u = avg_usg.call(p.id)
          w = (m > 0 ? m : 8.0)
          w *= (1.0 + (u / 100.0) * 0.35)
          weights[p.id] = [w, 5.0].max
        end

        wsum = weights.values.sum.to_f
        return {} if wsum <= 0.0
        weights.transform_values { |w| pool.to_f * (w / wsum) }
      end

      %w[G F C OTHER].each do |grp|
        outs = out_by_group[grp] || []
        recs = active_by_group[grp] || []
        next if outs.blank?

        grp_pool_usg = outs.sum { |p| avg_usg.call(p.id) } * OUT_USAGE_TRANSFER
        grp_pool_ast = outs.sum { |p| avg_ast.call(p.id) } * OUT_AST_TRANSFER
        grp_pool_trb = outs.sum { |p| avg_trb.call(p.id) } * OUT_REB_TRANSFER

        distribute.call(grp_pool_usg, recs).each { |pid, v| deltas[pid][:usage_delta] += v / 5.0 }
        distribute.call(grp_pool_trb, recs).each { |pid, v| deltas[pid][:rebound_delta] += v / 5.0 }
        distribute.call(grp_pool_ast, recs).each { |pid, v| deltas[pid][:assist_delta] += v / 5.0 }

        pool_usg -= grp_pool_usg
        pool_ast -= grp_pool_ast
        pool_trb -= grp_pool_trb
      end

      # leftover to all active
      distribute.call(pool_usg, active_players).each { |pid, v| deltas[pid][:usage_delta] += v / 6.0 } if pool_usg > 0.0
      distribute.call(pool_trb, active_players).each { |pid, v| deltas[pid][:rebound_delta] += v / 6.0 } if pool_trb > 0.0
      distribute.call(pool_ast, active_players).each { |pid, v| deltas[pid][:assist_delta] += v / 6.0 } if pool_ast > 0.0

      deltas
    end

    # -------------------------
    # On/Off history deltas (rates only)
    # Skips OUT players who have not appeared in team's last WINDOW_GAMES games.
    # -------------------------
    def build_onoff_deltas(team, active_players, out_players, has_usg:, has_ast_pct:, has_trb_pct:)
      out_ids = out_players.map(&:id)
      return {} if out_ids.blank? || active_players.blank?

      active_ids = active_players.map(&:id)

      baseline = baseline_avgs_for_players(
        active_ids,
        has_usg: has_usg,
        has_ast_pct: has_ast_pct,
        has_trb_pct: has_trb_pct
      )

      team_games = Game.where(season_id: @season.id)
                      .where("home_team_id = ? OR visitor_team_id = ?", team.id, team.id)
                      .order(date: :desc)
                      .limit(ONOFF_LOOKBACK_GAMES)
                      .pluck(:id, :date)

      return {} if team_games.blank?

      team_game_ids = team_games.map(&:first)
      game_date_by_id = team_games.to_h

      recent_team_game_ids = team_game_ids.first(WINDOW_GAMES)

      pluck_cols = [:game_id, :player_id, :minutes_played]
      pluck_cols << :usage_pct if has_usg
      pluck_cols << :assist_pct if has_ast_pct
      pluck_cols << :total_rebound_pct if has_trb_pct

      bs = BoxScore.where(game_id: team_game_ids, player_id: (active_ids + out_ids).uniq).pluck(*pluck_cols)

      by_game = Hash.new { |h, k| h[k] = {} }
      by_player_game_ids = Hash.new { |h, k| h[k] = Set.new }

      bs.each do |row|
        gid = row[0]
        pid = row[1]
        mp  = row[2]

        idx = 3
        usg  = has_usg     ? row[idx].tap { idx += 1 } : nil
        astp = has_ast_pct ? row[idx].tap { idx += 1 } : nil
        trbp = has_trb_pct ? row[idx].tap { idx += 1 } : nil

        mins = minutes_to_float(mp)

        by_game[gid][pid] = {
          minutes: mins,
          usage_pct: usg,
          assist_pct: astp,
          rebound_pct: trbp
        }

        by_player_game_ids[pid] << gid
      end

      # Only keep OUT players who appeared (mins > 0) in team's last WINDOW_GAMES games
      relevant_out_ids = out_ids.select do |out_pid|
        recent_team_game_ids.any? do |gid|
          r = by_game[gid][out_pid]
          r && r[:minutes].to_f > 0.0
        end
      end

      return {} if relevant_out_ids.blank?

      deltas = Hash.new do |h, k|
        h[k] = { usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0, samples: 0 }
      end

      relevant_out_ids.each do |out_pid|
        # Find first appearance date (within lookback) to avoid “pre-rookie” noise
        first_date = nil
        team_games.sort_by { |(_, d)| d }.each do |(gid, date)|
          r = by_game[gid][out_pid]
          next if r.nil?
          next unless r[:minutes].to_f > 0.0
          first_date = date
          break
        end
        next if first_date.nil?

        eligible_game_ids = team_game_ids.select do |gid|
          d = game_date_by_id[gid]
          d && d >= first_date
        end

        out_games = eligible_game_ids.select do |gid|
          has_row = by_player_game_ids[out_pid].include?(gid)
          if !has_row
            true
          else
            r = by_game[gid][out_pid]
            r.nil? || r[:minutes].to_f <= 0.0
          end
        end

        out_games = out_games.first(ONOFF_SAMPLE_CAP)
        next if out_games.size < ONOFF_SAMPLE_MIN

        active_ids.each do |pid|
          rows = out_games.map { |gid| by_game[gid][pid] }.compact
          next if rows.size < ONOFF_SAMPLE_MIN

          usg_arr = has_usg ? rows.map { |r| r[:usage_pct] }.compact.map(&:to_f) : []
          ast_arr = has_ast_pct ? rows.map { |r| r[:assist_pct] }.compact.map(&:to_f) : []
          trb_arr = has_trb_pct ? rows.map { |r| r[:rebound_pct] }.compact.map(&:to_f) : []

          usg_val = usg_arr.any? ? (usg_arr.sum / usg_arr.size) : nil
          ast_val = ast_arr.any? ? (ast_arr.sum / ast_arr.size) : nil
          trb_val = trb_arr.any? ? (trb_arr.sum / trb_arr.size) : nil

          base = baseline[pid] || { usage_pct: 0.0, assist_pct: 0.0, rebound_pct: 0.0 }

          deltas[pid][:usage_delta]   += ((usg_val.nil? ? base[:usage_pct] : usg_val) - base[:usage_pct]) if has_usg
          deltas[pid][:assist_delta]  += ((ast_val.nil? ? base[:assist_pct] : ast_val) - base[:assist_pct]) if has_ast_pct
          deltas[pid][:rebound_delta] += ((trb_val.nil? ? base[:rebound_pct] : trb_val) - base[:rebound_pct]) if has_trb_pct

          deltas[pid][:samples] += out_games.size
        end
      end

      out_count = relevant_out_ids.size.to_f
      output = {}

      deltas.each do |pid, h|
        samples = h[:samples].to_i
        next if samples <= 0

        usage_delta   = h[:usage_delta] / out_count
        rebound_delta = h[:rebound_delta] / out_count
        assist_delta  = h[:assist_delta] / out_count

        w = 0.15 * samples
        w = ONOFF_BLEND_MAX if w > ONOFF_BLEND_MAX
        w = 0.0 if w < 0.0

        output[pid] = {
          usage_delta: usage_delta,
          rebound_delta: rebound_delta,
          assist_delta: assist_delta,
          weight: w
        }
      end

      output
    end

    def normalize_minutes_to_team_total(mins_by_pid, target_total: TEAM_TOTAL_MINUTES, floors_by_pid: {})
      # mins_by_pid is "pre minutes" already clamped.
      # floors_by_pid optional, but we also apply smart floors/caps based on player history
      # if gather_inputs provides minutes_profile via inputs (we store that in mins_by_pid only),
      # so caps/floors MUST be computed elsewhere.
      #
      # Since this method only receives mins_by_pid, we implement generic behavior:
      # - Apply explicit floors_by_pid (your "star floors" if you want them later)
      # - Apply a soft cap to stop unrealistic inflation
      #
      # For caps, we use a conservative rule:
      #   cap = [pre_minutes + 6, 38].min
      # Which prevents someone from being normalized from 24 -> 38 just because the pool is missing.
      #
      # You can tighten/loosen the +6.

      return mins_by_pid if mins_by_pid.blank?

      mins = mins_by_pid.transform_values { |v| v.to_f }

      # 1) Apply explicit floors (if any)
      floors_by_pid.each do |pid, floor|
        next unless mins.key?(pid)
        mins[pid] = [mins[pid], floor.to_f].max
      end

      # 2) Apply soft caps relative to the player’s pre minutes
      caps_by_pid = {}
      mins.each do |pid, m|
        caps_by_pid[pid] = [m.to_f + 6.0, MINUTES_MAX].min
      end

      # 3) Now scale toward target_total, but respect floors/caps.
      # Iterative water-filling:
      5.times do
        total = mins.values.sum.to_f
        break if total <= 0.0

        diff = target_total.to_f - total
        break if diff.abs < 0.01

        if diff > 0
          # Need to add minutes to those under cap
          receivers = mins.select { |pid, m| m.to_f < (caps_by_pid[pid].to_f - 0.001) }
          break if receivers.blank?

          wsum = receivers.values.sum.to_f
          wsum = receivers.size.to_f if wsum <= 0.0

          receivers.each do |pid, m|
            w = (m.to_f > 0 ? m.to_f : 1.0)
            w = w / wsum
            mins[pid] = [mins[pid] + (diff * w), caps_by_pid[pid]].min
          end
        else
          # Need to remove minutes from those above floor (explicit floor if present, else 0)
          diff_abs = diff.abs
          floors = floors_by_pid.transform_values(&:to_f)
          donors = mins.select { |pid, m| m.to_f > (floors.fetch(pid, 0.0) + 0.001) }
          break if donors.blank?

          dsum = donors.values.sum.to_f
          dsum = donors.size.to_f if dsum <= 0.0

          donors.each do |pid, m|
            w = (m.to_f > 0 ? m.to_f : 1.0)
            w = w / dsum
            new_m = mins[pid] - (diff_abs * w)
            mins[pid] = [new_m, floors.fetch(pid, 0.0)].max
          end
        end
      end

      # 4) Final clamp and final renormalize (small drift)
      mins = mins.transform_values { |m| clamp_minutes(m) }

      total = mins.values.sum.to_f
      if total > 0.0 && (target_total.to_f - total).abs > 0.05
        factor = target_total.to_f / total
        mins = mins.transform_values { |m| clamp_minutes(m.to_f * factor) }
      end

      mins
    end




    def baseline_avgs_for_players(player_ids, has_usg:, has_ast_pct:, has_trb_pct:)
      bs = BoxScore.joins(:game)
                   .where(player_id: player_ids, games: { season_id: @season.id })
                   .where.not(minutes_played: [nil, "", "0:00"])
                   .order("games.date DESC")
                   .pluck(
                     :player_id, :minutes_played,
                     (has_usg ? :usage_pct : nil),
                     (has_ast_pct ? :assist_pct : nil),
                     (has_trb_pct ? :total_rebound_pct : nil)
                   )

      mins_map = Hash.new { |h, k| h[k] = [] }
      usg_map  = Hash.new { |h, k| h[k] = [] }
      ast_map  = Hash.new { |h, k| h[k] = [] }
      trb_map  = Hash.new { |h, k| h[k] = [] }

      bs.each do |pid, mp, usg, astp, trbp|
        next if mins_map[pid].size >= WINDOW_GAMES
        m = minutes_to_float(mp)
        next if m <= 0.0

        mins_map[pid] << m
        usg_map[pid] << usg.to_f if usg.present?
        ast_map[pid] << astp.to_f if astp.present?
        trb_map[pid] << trbp.to_f if trbp.present?
      end

      out = {}
      player_ids.each do |pid|
        mins = mins_map[pid]
        out[pid] = {
          minutes: (mins.any? ? projected_minutes_from_recent(mins) : 0.0),
          usage_pct: (usg_map[pid].any? ? (usg_map[pid].sum / usg_map[pid].size) : 0.0),
          assist_pct: (ast_map[pid].any? ? (ast_map[pid].sum / ast_map[pid].size) : 0.0),
          rebound_pct: (trb_map[pid].any? ? (trb_map[pid].sum / trb_map[pid].size) : 0.0)
        }
      end
      out
    end

    # -------------------------
    # Projection: minutes -> stats
    # -------------------------
    def project_stats(inputs, explainer: nil)
      opponent = inputs[:opponent]
      pos = inputs[:position]
      minutes = inputs[:minutes]
      rates = inputs[:rates]

      usg  = inputs[:pcts][:usage_pct].to_f
      trb  = inputs[:pcts][:rebound_pct].to_f
      astp = inputs[:pcts][:assist_pct].to_f

      usg_mult = 1.0 + ((usg - 20.0) / 100.0) * 0.25
      trb_mult = 1.0 + ((trb - 10.0) / 100.0) * 0.25
      ast_mult = 1.0 + ((astp - 15.0) / 100.0) * 0.20

      explainer&.add(
        step: "Multipliers (Role)",
        detail: "Multipliers derived from USG/TRB/AST %",
        data: {
          usg: usg.round(2),
          trb: trb.round(2),
          ast_pct: astp.round(2),
          usg_mult: usg_mult.round(4),
          trb_mult: trb_mult.round(4),
          ast_mult: ast_mult.round(4)
        }
      )

      dvp = opponent.defense_data_for(@season) || {}
      groups = position_buckets(pos)
      slice = groups.any? ? dvp.slice(*groups) : dvp

      pts_rank = avg_of(slice.values.map { |h| h["points_rank"] })
      reb_rank = avg_of(slice.values.map { |h| h["rebounds_rank"] })
      ast_rank = avg_of(slice.values.map { |h| h["assists_rank"] })

      pts_mult_raw = rank_to_multiplier_linear(pts_rank)
      reb_mult     = rank_to_multiplier_linear(reb_rank)
      ast_dvp_mult = rank_to_multiplier_linear(ast_rank)

      pts_mult = 1.0 + ((pts_mult_raw - 1.0) * 0.6)

      explainer&.add(
        step: "Matchup (DVP)",
        detail: "Position bucket DVP ranks -> multipliers",
        data: {
          pos: pos,
          buckets: groups,
          pts_rank: pts_rank&.round(2),
          reb_rank: reb_rank&.round(2),
          ast_rank: ast_rank&.round(2),
          pts_mult_raw: pts_mult_raw.round(4),
          pts_mult_used: pts_mult.round(4),
          reb_mult: reb_mult.round(4),
          ast_mult_dvp: ast_dvp_mult.round(4)
        }
      )

      rng = seeded_rng(inputs[:player].id)
      pts_rand = 1.0 + rng.rand(-VAR_POINTS..VAR_POINTS)
      reb_rand = 1.0 + rng.rand(-VAR_REBOUNDS..VAR_REBOUNDS)
      ast_rand = 1.0 + rng.rand(-VAR_ASSISTS..VAR_ASSISTS)
      th3_rand = 1.0 + rng.rand(-VAR_THREES..VAR_THREES)

      explainer&.add(
        step: "Micro Variance",
        detail: "Deterministic small RNG variance",
        data: {
          pts_rand: pts_rand.round(4),
          reb_rand: reb_rand.round(4),
          ast_rand: ast_rand.round(4),
          th3_rand: th3_rand.round(4)
        }
      )

      points   = (rates[:points_per_min]   * minutes * pts_mult     * usg_mult * pts_rand).round(2)
      rebounds = (rates[:rebounds_per_min] * minutes * reb_mult     * trb_mult * reb_rand).round(2)
      assists  = (rates[:assists_per_min]  * minutes * ast_dvp_mult * ast_mult * ast_rand).round(2)
      threes   = (rates[:threes_per_min]   * minutes * pts_mult     * usg_mult * th3_rand).round(2)

      points   = 0.0 if points.nan?   || points.infinite?
      rebounds = 0.0 if rebounds.nan? || rebounds.infinite?
      assists  = 0.0 if assists.nan?  || assists.infinite?
      threes   = 0.0 if threes.nan?   || threes.infinite?

      points   = [points, 0.0].max
      rebounds = [rebounds, 0.0].max
      assists  = [assists, 0.0].max
      threes   = [threes, 0.0].max

      points_cap = minutes * 1.25
      points = [points, points_cap].min

      explainer&.add(
        step: "Final Outputs",
        detail: "Rates * minutes * multipliers",
        data: {
          minutes: minutes.round(2),
          points: points.round(2),
          rebounds: rebounds.round(2),
          assists: assists.round(2),
          threes: threes.round(2)
        }
      )

      { points: points, rebounds: rebounds, assists: assists, threes: threes }
    end

    def rank_to_multiplier_linear(rank)
      return 1.0 if rank.nil?

      r = rank.to_f
      r = 1.0 if r < 1.0
      r = 30.0 if r > 30.0

      t = (r - 1.0) / 29.0
      (DVP_MIN_MULT + (DVP_MAX_MULT - DVP_MIN_MULT) * t).round(4)
    end

    def seeded_rng(player_id)
      seed = Zlib.crc32("#{@date.iso8601}-#{MODEL_VERSION}-#{player_id}")
      Random.new(seed)
    end

    def avg_of(arr)
      arr = arr.compact
      return nil if arr.empty?
      arr.sum.to_f / arr.size
    end

    def position_buckets(pos)
      case pos
      when "PG" then %w[PG G]
      when "SG" then %w[SG G]
      when "SF" then %w[SF F]
      when "PF" then %w[PF F]
      when "C"  then %w[C]
      else []
      end
    end
  end
end
