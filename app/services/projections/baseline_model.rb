# app/services/projections/baseline_model.rb
require "zlib"

module ::Projections
  class BaselineModel
    MODEL_VERSION = "baseline_v1".freeze

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
    VAR_THREES = 0.05

    # Minutes tuning
    MINUTES_CLAMP_BAND = 2.0
    MINUTES_MAX = 38.0
    MINUTES_MIN = 0.0

    # Injury redistribution tuning (conservative)
    USG_BOOST_CAP = 3.0
    REB_BOOST_CAP = 2.0
    AST_BOOST_CAP = 2.0

    OUT_MINUTES_TRANSFER = 0.65
    OUT_USAGE_TRANSFER   = 0.65
    OUT_REB_TRANSFER     = 0.60
    OUT_AST_TRANSFER     = 0.60

    # NEW: cap minutes delta so redistribution cannot blow players to 40 every time
    INJURY_MINUTES_BOOST_CAP = 4

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
      players = Player.where(id: eligible_player_ids).includes(:team, :health)

      puts "[BASELINE] Eligible players (>#{MIN_AVG_MINUTES} min avg, >=#{MIN_GAMES} games, not Out): #{players.size}"

      injury_map_by_team = build_injury_adjustments(team_ids)

      count = 0

      players.find_each do |player|
        opp = next_opponent_for(player, todays_games)
        next unless opp

        inputs = gather_inputs(player, opp)
        next if inputs.blank?

        team_injury = injury_map_by_team[player.team_id] || {}
        deltas = team_injury[player.id] || {}

        raw_minutes_delta = deltas.fetch(:minutes_delta, 0.0)
        capped_minutes_delta = clamp_delta(raw_minutes_delta, INJURY_MINUTES_BOOST_CAP)
        expected_minutes = clamp_minutes(inputs[:minutes] + capped_minutes_delta)

        base_usg = inputs[:pcts][:usage_pct]
        base_reb = inputs[:pcts][:rebound_pct]
        base_ast = inputs[:pcts][:assist_pct]

        adj_usg = clamp_pct(base_usg + deltas.fetch(:usage_delta, 0.0), base_usg, USG_BOOST_CAP)
        adj_reb = clamp_pct(base_reb + deltas.fetch(:rebound_delta, 0.0), base_reb, REB_BOOST_CAP)
        adj_ast = clamp_pct(base_ast + deltas.fetch(:assist_delta, 0.0), base_ast, AST_BOOST_CAP)

        inputs_for_projection = inputs.merge(
          minutes: expected_minutes,
          pcts: {
            usage_pct: adj_usg,
            rebound_pct: adj_reb,
            assist_pct: adj_ast
          }
        )

        outputs = project_stats(inputs_for_projection)

        projection = Projection.find_or_initialize_by(date: @date, player_id: player.id)
        projection.assign_attributes(
          projection_run_id: run.id,
          team_id: player.team_id,
          opponent_team_id: opp.id,
          position: inputs[:position],

          expected_minutes: expected_minutes,
          usage_pct: adj_usg,
          rebound_pct: adj_reb,
          assist_pct: adj_ast,

          proj_points: outputs[:points],
          proj_rebounds: outputs[:rebounds],
          proj_assists: outputs[:assists],
          proj_threes: outputs[:threes],
          proj_pa: outputs[:points] + outputs[:assists],
          proj_pr: outputs[:points] + outputs[:rebounds],
          proj_ra: outputs[:rebounds] + outputs[:assists],
          proj_pra: outputs[:points] + outputs[:rebounds] + outputs[:assists]
        )
        projection.save!
        count += 1
      rescue => e
        Rails.logger.warn "[::Projections::BaselineModel] #{player&.name || 'player'} failed: #{e.message}"
        next
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

    def clamp_delta(delta, cap)
      d = delta.to_f
      c = cap.to_f
      [[d, -c].max, c].min
    end

    # -------------------------
    # Eligibility / schedule
    # -------------------------
    def eligible_players_for(team_ids)
      Player
        .joins(box_scores: :game)
        .where(players: { team_id: team_ids })
        .where(games: { season_id: @season.id })
        .where.not(box_scores: { minutes_played: [nil, ""] })
        .group("players.id")
        .having(<<~SQL.squish)
          COUNT(box_scores.id) >= #{MIN_GAMES}
          AND AVG(
            (CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", 1) AS UNSIGNED) * 60) +
            CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", -1) AS UNSIGNED)
          ) > #{(MIN_AVG_MINUTES * 60).to_i}
        SQL
        .joins("LEFT JOIN healths ON healths.player_id = players.id")
        .where('COALESCE(healths.status, "Healthy") <> "Out"')
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
                     .where.not(minutes_played: [nil, "", "0:00"])
                     .where.not(points: nil)
                     .order("games.date DESC")
                     .limit(WINDOW_GAMES)

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
        rows = bs_rel.pluck(
          :minutes_played, :points, rebound_count_col, :assists, :three_point_field_goals,
          (has_usg ? :usage_pct : nil),
          (has_ast_pct ? :assist_pct : nil),
          (has_trb_pct ? :total_rebound_pct : nil)
        )
      else
        o_col = cols.include?("offensive_rebounds") ? :offensive_rebounds : nil
        d_col = cols.include?("defensive_rebounds") ? :defensive_rebounds : nil
        rows = bs_rel.pluck(
          :minutes_played, :points, o_col, d_col, :assists, :three_point_field_goals,
          (has_usg ? :usage_pct : nil),
          (has_ast_pct ? :assist_pct : nil),
          (has_trb_pct ? :total_rebound_pct : nil)
        )
      end

      return nil if rows.blank? || rows.size < MIN_GAMES

      totals = accumulate_totals(rows, rebound_count_col: rebound_count_col)
      return nil if totals[:games] < MIN_GAMES
      return nil if totals[:total_minutes] <= 0.0

      avg_minutes = totals[:total_minutes] / totals[:games].to_f
      return nil if avg_minutes < MIN_AVG_MINUTES

      expected_minutes = projected_minutes_from_recent(totals[:minutes_list])

      ppm_points   = totals[:points].to_f / totals[:total_minutes]
      ppm_rebounds = totals[:rebounds].to_f / totals[:total_minutes]
      ppm_assists  = totals[:assists].to_f / totals[:total_minutes]
      ppm_threes = totals[:threes].to_f / totals[:total_minutes]

      base_usg = totals[:usage_pct_vals].any? ? (totals[:usage_pct_vals].sum / totals[:usage_pct_vals].size) : 0.0
      base_ast = totals[:assist_pct_vals].any? ? (totals[:assist_pct_vals].sum / totals[:assist_pct_vals].size) : 0.0
      base_trb = totals[:trb_pct_vals].any? ? (totals[:trb_pct_vals].sum / totals[:trb_pct_vals].size) : 0.0

      {
        player: player,
        opponent: opponent,
        position: player.position,
        minutes: expected_minutes,
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
        reb    = row[2]
        ast    = row[3]
        th3    = row[4]
        usg    = row[5]
        ast_pct= row[6]
        trb_pct= row[7]
      else
        oreb   = row[2]
        dreb   = row[3]
        reb    = oreb.to_i + dreb.to_i
        ast    = row[4]
        th3    = row[5]
        usg    = row[6]
        ast_pct= row[7]
        trb_pct= row[8]
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

    def projected_minutes_from_recent(minutes_list)
      return 0.0 if minutes_list.blank?

      n = minutes_list.size
      weights = n.downto(1).to_a
      weighted = minutes_list.zip(weights).sum { |m, w| m.to_f * w } / weights.sum.to_f

      avg = minutes_list.sum.to_f / n
      lower = [avg - MINUTES_CLAMP_BAND, 0.0].max
      upper = avg + MINUTES_CLAMP_BAND

      [[weighted, lower].max, upper].min
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
    # Injury adjustments (on/off + redistribution blend)
    # -------------------------
    def build_injury_adjustments(team_ids)
      result = {}

      team_players = Player.includes(:health).where(team_id: team_ids).to_a
      players_by_team = team_players.group_by(&:team_id)

      cols = BoxScore.column_names
      has_usg = cols.include?("usage_pct")
      has_ast_pct = cols.include?("assist_pct")
      has_trb_pct = cols.include?("total_rebound_pct")

      Team.where(id: team_ids).find_each do |team|
        roster = players_by_team[team.id] || []
        out_players = roster.select { |p| p.health&.status.to_s == "Out" }
        active_players = roster.reject { |p| p.health&.status.to_s == "Out" }

        if out_players.blank? || active_players.blank?
          result[team.id] = {}
          next
        end

        redistribution = build_redistribution_deltas(team, roster, out_players, active_players)
        onoff = build_onoff_deltas(team, active_players, out_players, has_usg: has_usg, has_ast_pct: has_ast_pct, has_trb_pct: has_trb_pct)

        deltas_for_team = Hash.new { |h, k| h[k] = { minutes_delta: 0.0, usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0 } }

        active_players.each do |p|
          ro = redistribution[p.id] || {}
          oo = onoff[p.id] || {}

          w = oo.fetch(:weight, 0.0)
          w = ONOFF_BLEND_MAX if w > ONOFF_BLEND_MAX
          w = ONOFF_BLEND_MIN if w < ONOFF_BLEND_MIN

          deltas_for_team[p.id][:minutes_delta] =
            (oo.fetch(:minutes_delta, 0.0) * w) + (ro.fetch(:minutes_delta, 0.0) * (1.0 - w))

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

    def build_redistribution_deltas(team, roster, out_players, active_players)
      cols = BoxScore.column_names
      has_usg = cols.include?("usage_pct")
      has_ast_pct = cols.include?("assist_pct")
      has_trb_pct = cols.include?("total_rebound_pct")

      player_ids = roster.map(&:id)

      bs_rows = BoxScore
        .joins(:game)
        .where(player_id: player_ids, games: { season_id: @season.id })
        .where.not(minutes_played: [nil, "", "0:00"])
        .order("games.date DESC")
        .limit(WINDOW_GAMES * player_ids.size)
        .pluck(
          :player_id,
          :minutes_played,
          (has_usg ? :usage_pct : nil),
          (has_ast_pct ? :assist_pct : nil),
          (has_trb_pct ? :total_rebound_pct : nil)
        )

      mins_map = Hash.new { |h, k| h[k] = [] }
      usg_map  = Hash.new { |h, k| h[k] = [] }
      ast_map  = Hash.new { |h, k| h[k] = [] }
      trb_map  = Hash.new { |h, k| h[k] = [] }

      bs_rows.each do |pid, mp, usg, astp, trbp|
        next if mins_map[pid].size >= WINDOW_GAMES
        m = minutes_to_float(mp)
        next if m <= 0.0

        mins_map[pid] << m
        usg_map[pid] << usg.to_f if usg.present?
        ast_map[pid] << astp.to_f if astp.present?
        trb_map[pid] << trbp.to_f if trbp.present?
      end

      avg_mins = ->(pid) { mins_map[pid].any? ? (mins_map[pid].sum / mins_map[pid].size) : 0.0 }
      avg_usg  = ->(pid) { usg_map[pid].any? ? (usg_map[pid].sum / usg_map[pid].size) : 0.0 }
      avg_ast  = ->(pid) { ast_map[pid].any? ? (ast_map[pid].sum / ast_map[pid].size) : 0.0 }
      avg_trb  = ->(pid) { trb_map[pid].any? ? (trb_map[pid].sum / trb_map[pid].size) : 0.0 }

      pool_minutes = out_players.sum { |p| avg_mins.call(p.id) } * OUT_MINUTES_TRANSFER
      pool_usg     = out_players.sum { |p| avg_usg.call(p.id) }  * OUT_USAGE_TRANSFER
      pool_ast     = out_players.sum { |p| avg_ast.call(p.id) }  * OUT_AST_TRANSFER
      pool_trb     = out_players.sum { |p| avg_trb.call(p.id) }  * OUT_REB_TRANSFER

      group_for = ->(pos) do
        case pos
        when "PG", "SG" then "G"
        when "SF", "PF" then "F"
        when "C"        then "C"
        else "OTHER"
        end
      end

      active_by_group = active_players.group_by { |p| group_for.call(p.position) }
      out_by_group    = out_players.group_by { |p| group_for.call(p.position) }

      deltas_for_team = Hash.new { |h, k| h[k] = { minutes_delta: 0.0, usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0 } }

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

        grp_pool_minutes = outs.sum { |p| avg_mins.call(p.id) } * OUT_MINUTES_TRANSFER
        grp_pool_usg     = outs.sum { |p| avg_usg.call(p.id) }  * OUT_USAGE_TRANSFER
        grp_pool_ast     = outs.sum { |p| avg_ast.call(p.id) }  * OUT_AST_TRANSFER
        grp_pool_trb     = outs.sum { |p| avg_trb.call(p.id) }  * OUT_REB_TRANSFER

        distribute.call(grp_pool_minutes, recs).each { |pid, v| deltas_for_team[pid][:minutes_delta] += v }
        distribute.call(grp_pool_usg, recs).each    { |pid, v| deltas_for_team[pid][:usage_delta] += v / 5.0 }
        distribute.call(grp_pool_trb, recs).each    { |pid, v| deltas_for_team[pid][:rebound_delta] += v / 5.0 }
        distribute.call(grp_pool_ast, recs).each    { |pid, v| deltas_for_team[pid][:assist_delta] += v / 5.0 }

        pool_minutes -= grp_pool_minutes
        pool_usg     -= grp_pool_usg
        pool_ast     -= grp_pool_ast
        pool_trb     -= grp_pool_trb
      end

      all_active = active_players
      distribute.call(pool_minutes, all_active).each { |pid, v| deltas_for_team[pid][:minutes_delta] += v } if pool_minutes > 0.0
      distribute.call(pool_usg, all_active).each     { |pid, v| deltas_for_team[pid][:usage_delta] += v / 6.0 } if pool_usg > 0.0
      distribute.call(pool_trb, all_active).each     { |pid, v| deltas_for_team[pid][:rebound_delta] += v / 6.0 } if pool_trb > 0.0
      distribute.call(pool_ast, all_active).each     { |pid, v| deltas_for_team[pid][:assist_delta] += v / 6.0 } if pool_ast > 0.0

      deltas_for_team
    end

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

        # Track that this player has a row in this game (important for "out = no row")
        by_player_game_ids[pid] << gid
      end

      # Guard: only consider games on/after out player's first actual appearance (mins > 0)
      first_active_date_by_out_pid = {}

      out_ids.each do |out_pid|
        first_date = nil

        team_games.sort_by { |(_, d)| d }.each do |(gid, date)|
          r = by_game[gid][out_pid]
          next if r.nil?
          next unless r[:minutes].to_f > 0.0
          first_date = date
          break
        end

        next if first_date.nil?
        first_active_date_by_out_pid[out_pid] = first_date
      end

      return {} if first_active_date_by_out_pid.blank?

      deltas = Hash.new do |h, k|
        h[k] = { minutes_delta: 0.0, usage_delta: 0.0, rebound_delta: 0.0, assist_delta: 0.0, samples: 0 }
      end

      first_active_date_by_out_pid.each do |out_pid, first_active_date|
        eligible_game_ids = team_game_ids.select do |gid|
          d = game_date_by_id[gid]
          d && d >= first_active_date
        end

        # OUT definition aligned with your scraper:
        # - out if NO box score row exists for out player in that game
        # - OR minutes <= 0.0 (covers legacy rows that might exist with 0:00)
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

          avg_mins = rows.sum { |r| r[:minutes].to_f } / rows.size

          usg_arr = has_usg ? rows.map { |r| r[:usage_pct] }.compact.map(&:to_f) : []
          ast_arr = has_ast_pct ? rows.map { |r| r[:assist_pct] }.compact.map(&:to_f) : []
          trb_arr = has_trb_pct ? rows.map { |r| r[:rebound_pct] }.compact.map(&:to_f) : []

          usg_val = usg_arr.any? ? (usg_arr.sum / usg_arr.size) : nil
          ast_val = ast_arr.any? ? (ast_arr.sum / ast_arr.size) : nil
          trb_val = trb_arr.any? ? (trb_arr.sum / trb_arr.size) : nil

          base = baseline[pid] || { minutes: 0.0, usage_pct: 0.0, assist_pct: 0.0, rebound_pct: 0.0 }

          deltas[pid][:minutes_delta] += (avg_mins - base[:minutes])
          deltas[pid][:usage_delta]   += ((usg_val.nil? ? base[:usage_pct] : usg_val) - base[:usage_pct]) if has_usg
          deltas[pid][:assist_delta]  += ((ast_val.nil? ? base[:assist_pct] : ast_val) - base[:assist_pct]) if has_ast_pct
          deltas[pid][:rebound_delta] += ((trb_val.nil? ? base[:rebound_pct] : trb_val) - base[:rebound_pct]) if has_trb_pct

          deltas[pid][:samples] += out_games.size
        end
      end

      out_count = first_active_date_by_out_pid.size.to_f
      output = {}

      deltas.each do |pid, h|
        samples = h[:samples].to_i
        next if samples <= 0

        minutes_delta = h[:minutes_delta] / out_count
        usage_delta   = h[:usage_delta] / out_count
        rebound_delta = h[:rebound_delta] / out_count
        assist_delta  = h[:assist_delta] / out_count

        w = 0.15 * samples
        w = ONOFF_BLEND_MAX if w > ONOFF_BLEND_MAX
        w = 0.0 if w < 0.0

        output[pid] = {
          minutes_delta: minutes_delta,
          usage_delta: usage_delta,
          rebound_delta: rebound_delta,
          assist_delta: assist_delta,
          weight: w
        }
      end

      output
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
          minutes: (mins.any? ? (mins.sum / mins.size) : 0.0),
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
    def project_stats(inputs)
      opponent = inputs[:opponent]
      pos = inputs[:position]
      minutes = inputs[:minutes]
      rates = inputs[:rates]

      usg = inputs[:pcts][:usage_pct].to_f
      trb = inputs[:pcts][:rebound_pct].to_f
      astp = inputs[:pcts][:assist_pct].to_f

      usg_mult = 1.0 + ((usg - 20.0) / 100.0) * 0.25
      trb_mult = 1.0 + ((trb - 10.0) / 100.0) * 0.25
      ast_mult = 1.0 + ((astp - 15.0) / 100.0) * 0.20

      dvp = opponent.defense_data_for(@season) || {}
      groups = position_buckets(pos)
      slice = groups.any? ? dvp.slice(*groups) : dvp

      pts_rank = avg_of(slice.values.map { |h| h["points_rank"] })
      reb_rank = avg_of(slice.values.map { |h| h["rebounds_rank"] })
      ast_rank = avg_of(slice.values.map { |h| h["assists_rank"] })

      pts_mult = rank_to_multiplier_linear(pts_rank)
      reb_mult = rank_to_multiplier_linear(reb_rank)
      ast_dvp_mult = rank_to_multiplier_linear(ast_rank)

      pts_mult = 1.0 + ((pts_mult - 1.0) * 0.6)

      rng = seeded_rng(inputs[:player].id)
      pts_rand = 1.0 + rng.rand(-VAR_POINTS..VAR_POINTS)
      reb_rand = 1.0 + rng.rand(-VAR_REBOUNDS..VAR_REBOUNDS)
      ast_rand = 1.0 + rng.rand(-VAR_ASSISTS..VAR_ASSISTS)
      th3_rand = 1.0 + rng.rand(-VAR_THREES..VAR_THREES)

      points   = (rates[:points_per_min]   * minutes * pts_mult     * usg_mult * pts_rand).round(2)
      rebounds = (rates[:rebounds_per_min] * minutes * reb_mult     * trb_mult * reb_rand).round(2)
      assists  = (rates[:assists_per_min]  * minutes * ast_dvp_mult * ast_mult * ast_rand).round(2)
      threes = (rates[:threes_per_min] * minutes * pts_mult * usg_mult * th3_rand).round(2)

      points   = 0.0 if points.nan? || points.infinite?
      rebounds = 0.0 if rebounds.nan? || rebounds.infinite?
      assists  = 0.0 if assists.nan? || assists.infinite?
      threes = 0.0 if threes.nan? || threes.infinite?

      points = [points, 0.0].max
      rebounds = [rebounds, 0.0].max
      assists = [assists, 0.0].max
      threes = [threes, 0.0].max

      points_cap = minutes * 1.25
      points = [points, points_cap].min

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
