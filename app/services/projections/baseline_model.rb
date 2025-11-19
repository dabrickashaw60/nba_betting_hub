# app/services/projections/dvp_only_model.rb
module ::Projections
  class BaselineModel
    MODEL_VERSION = "baseline_v1".freeze

    # rank 1 = hardest defense, 30 = easiest
    # we scale linearly: 1 → 0.85, 30 → 1.15
    DVP_MIN = 0.85
    DVP_MAX = 1.15

    def initialize(date:)
      @date = date
      @season = Season.find_by(current: true)
      raise "No current season" unless @season
    end



    def run!
      ProjectionRun.where(date: @date, model_version: MODEL_VERSION).destroy_all
      Projection.where(date: @date).destroy_all
      run = ::ProjectionRun.find_or_initialize_by(date: @date, model_version: MODEL_VERSION)
      return run if run.success?

      run.update!(status: :running, started_at: Time.current, notes: nil, projections_count: 0)

      todays_games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
      team_ids = todays_games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq
      return mark_success(run) if team_ids.blank?

      # Eligible: >15 min avg last 5, not Out
      eligible_player_ids = Player
        .joins(box_scores: :game)
        .where(players: { team_id: team_ids })
        .where(games: { season_id: @season.id })
        .where.not(box_scores: { minutes_played: [nil, ""] })
        .group('players.id')
        .having(<<~SQL.squish)
          COUNT(box_scores.id) >= 5
          AND AVG(
            (CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", 1) AS UNSIGNED) * 60) +
            CAST(SUBSTRING_INDEX(box_scores.minutes_played, ":", -1) AS UNSIGNED)
          ) > 900
        SQL
        .joins('LEFT JOIN healths ON healths.player_id = players.id')
        .where('COALESCE(healths.status, "Healthy") <> "Out"')
        .pluck(:id)

      players = Player.where(id: eligible_player_ids).includes(:team)
      puts "[DVP_ONLY] Eligible players (>15 min last5 & not Out): #{players.size}"

      count = 0

      players.find_each do |player|
        opp = next_opponent_for(player, todays_games)
        next unless opp

        inputs = gather_inputs(player, opp)
        next if inputs.blank?

        outputs = project_stats(inputs)

        puts "[OK DVP] #{player.name} vs #{opp.abbreviation} "\
             "PTS=#{outputs[:points].round(1)} REB=#{outputs[:rebounds].round(1)} AST=#{outputs[:assists].round(1)}"

        projection = Projection.find_or_initialize_by(date: @date, player_id: player.id)
        projection.assign_attributes(
          projection_run_id: run.id,
          team_id: player.team_id,
          opponent_team_id: opp.id,
          position: inputs[:position],
          proj_points: outputs[:points],
          proj_rebounds: outputs[:rebounds],
          proj_assists: outputs[:assists],
          proj_pa: outputs[:points] + outputs[:assists],
          proj_pr: outputs[:points] + outputs[:rebounds],
          proj_ra: outputs[:rebounds] + outputs[:assists],
          proj_pra: outputs[:points] + outputs[:rebounds] + outputs[:assists]
        )
        projection.save!
        count += 1
      rescue => e
        Rails.logger.warn "[::Projections::DvpOnly] #{player.name} failed: #{e.message}"
        next
      end

      run.update!(projections_count: count)
      mark_success(run)
    rescue => e
      run&.update!(status: :error, finished_at: Time.current, notes: e.message)
      raise
    end

    private

    def mark_success(run)
      run.update!(status: :success, finished_at: Time.current)
      run
    end

    def next_opponent_for(player, todays_games)
      g = todays_games.detect { |game| game.home_team_id == player.team_id || game.visitor_team_id == player.team_id }
      return nil unless g
      g.home_team_id == player.team_id ? g.visitor_team : g.home_team
    end

    # ───────────────────────────────
    # INPUTS
    # ───────────────────────────────
    def gather_inputs(player, opponent)
      bs = player.box_scores
                .joins(:game)
                .where(games: { season_id: @season.id })
                .where.not(minutes_played: [nil, "", "0:00"])
                .where.not(points: nil)
                .order("games.date DESC")
                .limit(5)
                .distinct


      return nil if bs.blank?
      minutes_avg = avg_minutes(bs)
      return nil if minutes_avg < 15

      # L5 baseline values (explicit lists so we can log/verify)
      pts_vals = bs.pluck(:points)
      reb_vals = rebound_values_for(bs)
      ast_vals = bs.pluck(:assists)

      # Averages
      pts_avg = pts_vals.compact.sum.to_f / pts_vals.compact.size
      reb_avg = reb_vals.compact.sum.to_f / reb_vals.compact.size
      ast_avg = ast_vals.compact.sum.to_f / ast_vals.compact.size

      # Debug: show the exact last-5 values used
      puts "[L5] #{player.name} P=#{pts_vals.inspect} R=#{reb_vals.inspect} A=#{ast_vals.inspect} "\
          "=> Avg P=#{pts_avg.round(2)} R=#{reb_avg.round(2)} A=#{ast_avg.round(2)}"

      {
        player: player,
        opponent: opponent,
        position: player.position,
        baseline: {
          points:   pts_avg,
          rebounds: reb_avg,
          assists:  ast_avg
        }
      }

    end

    # Choose the right rebound source across schemas
    def rebound_values_for(box_scores)
      cols = BoxScore.column_names
      if cols.include?("total_rebounds")
        box_scores.pluck(:total_rebounds)
      elsif cols.include?("rebounds")
        box_scores.pluck(:rebounds)
      else
        # Sum OREB + DREB if that’s what you store
        o = cols.include?("offensive_rebounds") ? box_scores.pluck(:offensive_rebounds) : []
        d = cols.include?("defensive_rebounds") ? box_scores.pluck(:defensive_rebounds) : []
        o.zip(d).map { |oi, di| oi.to_i + di.to_i }
      end
    end


    # ───────────────────────────────
    # PURE DVP SCALING
    # ───────────────────────────────
    def project_stats(inputs)
      b        = inputs[:baseline]
      opponent = inputs[:opponent]
      pos      = inputs[:position]
      dvp      = opponent.defense_data_for(@season) || {}

      groups = position_buckets(pos)
      slice  = dvp.slice(*groups)

      # average ranks across relevant groups
      pts_rank = avg_of(slice.values.map { |h| h["points_rank"] })
      reb_rank = avg_of(slice.values.map { |h| h["rebounds_rank"] })
      ast_rank = avg_of(slice.values.map { |h| h["assists_rank"] })

      pts_mult = rank_to_multiplier(pts_rank)
      reb_mult = rank_to_multiplier(reb_rank)
      ast_mult = rank_to_multiplier(ast_rank)

      puts "[DVP] #{inputs[:player].name} vs #{opponent.abbreviation} "\
           "ranks(P=#{pts_rank&.round(1)},R=#{reb_rank&.round(1)},A=#{ast_rank&.round(1)}) "\
           "mults(P=#{pts_mult},R=#{reb_mult},A=#{ast_mult}) "\
           "L5(P=#{b[:points]},R=#{b[:rebounds]},A=#{b[:assists]})"

      {
        points:   (b[:points]   * pts_mult).round(2),
        rebounds: (b[:rebounds] * reb_mult).round(2),
        assists:  (b[:assists]  * ast_mult).round(2)
      }
    end

    # ───────────────────────────────
    # HELPERS
    # ───────────────────────────────
    def rank_to_multiplier(rank)
      return [1.0, "neutral (no rank)"] unless rank

      rank = rank.to_f

      # Neutral (14–16): no adjustment
      return [1.0, "neutral (14–16)"] if rank.between?(14, 16)

      # ─────── HARD DEFENSE ZONES ───────
      case rank
      when 1..5
        mult = 0.75
        label = "very hard (↓ 25%)"
      when 6..10
        mult = 0.85
        label = "hard (↓ 15%)"
      when 11..13
        mult = 0.90
        label = "slightly hard (↓ 10%)"

      # ─────── EASY DEFENSE ZONES ───────
      when 17..20
        mult = 1.10
        label = "slightly easy (↑ 10%)"
      when 21..25
        mult = 1.15
        label = "easy (↑ 15%)"
      when 26..30
        mult = 1.25
        label = "very easy (↑ 25%)"
      else
        mult = 1.0
        label = "neutral"
      end

      [mult.round(4), label]
    end


    def project_stats(inputs)
      b        = inputs[:baseline]
      opponent = inputs[:opponent]
      pos      = inputs[:position]
      dvp      = opponent.defense_data_for(@season) || {}

      groups = position_buckets(pos)
      slice  = dvp.slice(*groups)

      pts_rank = avg_of(slice.values.map { |h| h["points_rank"] })
      reb_rank = avg_of(slice.values.map { |h| h["rebounds_rank"] })
      ast_rank = avg_of(slice.values.map { |h| h["assists_rank"] })

      pts_mult, pts_label = rank_to_multiplier(pts_rank)
      reb_mult, reb_label = rank_to_multiplier(reb_rank)
      ast_mult, ast_label = rank_to_multiplier(ast_rank)

      # 💡 dampen effect on points slightly vs rebounds/assists
      pts_adj_mult = 1.0 + ((pts_mult - 1.0) * 0.5)
      reb_adj_mult = reb_mult
      ast_adj_mult = ast_mult

      # 🎲 Add realistic nightly randomness
      rand_factor_points   = 1.0 + rand(-0.10..0.10)  # ±10% variability
      rand_factor_rebounds = 1.0 + rand(-0.15..0.15)  # ±15% variability
      rand_factor_assists  = 1.0 + rand(-0.20..0.20)  # ±20% variability

      points   = (b[:points]   * pts_adj_mult * rand_factor_points).round(2)
      rebounds = (b[:rebounds] * reb_adj_mult * rand_factor_rebounds).round(2)
      assists  = (b[:assists]  * ast_adj_mult * rand_factor_assists).round(2)

      {
        points:   points,
        rebounds: rebounds,
        assists:  assists
      }
    end


    def avg_minutes(box_scores)
      valid = box_scores.select { |g| g.minutes_played.present? }
      return 0.0 if valid.empty?
      total_sec = valid.sum do |g|
        m, s = g.minutes_played.split(":").map(&:to_i)
        (m * 60) + s
      end
      (total_sec / 60.0 / valid.size)
    end

    def avg_stat(bs, attr)
      return 0.0 if bs.empty?
      bs.sum(attr).to_f / bs.size
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
