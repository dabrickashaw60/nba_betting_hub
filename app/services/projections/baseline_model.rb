# app/services/::Projections/baseline_model.rb
module ::Projections
  class BaselineModel
    MODEL_VERSION = "baseline_v1".freeze

    def initialize(date:)
      @date = date
      @season = Season.find_by(current: true)
      raise "No current season" unless @season
    end

    def run!
      run = ::ProjectionRun.find_or_initialize_by(date: @date, model_version: MODEL_VERSION); return run if run.success?

      run.update!(status: :running, started_at: Time.current, notes: nil, projections_count: 0)

# Find today's games/teams (as you already do)
todays_games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
team_ids = todays_games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq
return mark_success(run) if team_ids.blank?

# Build an efficient eligible set:
# - same-team today
# - current season
# - at least 5 box scores with minutes
# - last-5 avg minutes > 15 (900 sec)
# - NOT Out (joins healths)
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
puts "[DEBUG] Eligible players (>15 min last5 & not Out): #{players.size}"



      count = 0
      players.find_each do |player|
  begin
    opp = next_opponent_for(player, todays_games)
    if opp.nil?
      puts "[SKIP] #{player.name} – no opponent found today"
      next
    end

    inputs = gather_inputs(player, opp)
    if inputs.blank?
      puts "[SKIP] #{player.name} – no inputs returned"
      next
    end

    outputs = project_stats(inputs)
    puts "[OK] #{player.name} vs #{opp.name} – mins=#{inputs[:expected_minutes].round(1)} usage=#{inputs[:usage_pct].round(1)} pts=#{outputs[:points]}"

    projection = Projection.find_or_initialize_by(
      date: @date,
      player_id: player.id
    )

    projection.assign_attributes(
      projection_run_id: run.id,
      team_id: player.team_id,
      opponent_team_id: opp.id,

      expected_minutes: inputs[:expected_minutes],
      usage_pct:        inputs[:usage_pct],
      position:         inputs[:position],
      injury_status:    inputs[:injury_status],
      dvp_pts_mult:     inputs[:dvp_pts_mult],
      dvp_reb_mult:     inputs[:dvp_reb_mult],
      dvp_ast_mult:     inputs[:dvp_ast_mult],

      proj_points:      outputs[:points],
      proj_rebounds:    outputs[:rebounds],
      proj_assists:     outputs[:assists],
      proj_threes:      outputs[:threes],
      proj_steals:      outputs[:steals],
      proj_blocks:      outputs[:blocks],
      proj_turnovers:   outputs[:turnovers],
      proj_plus_minus:  outputs[:plus_minus],

      proj_pa:  outputs[:points] + outputs[:assists],
      proj_pr:  outputs[:points] + outputs[:rebounds],
      proj_ra:  outputs[:rebounds] + outputs[:assists],
      proj_pra: outputs[:points] + outputs[:rebounds] + outputs[:assists]
    )

    projection.save!
    count += 1

        rescue => e
          Rails.logger.warn "[::Projections] #{player.name} failed: #{e.message}"
          next
        end
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

    def gather_inputs(player, opponent)
      # Skip entirely if player is OUT — no minutes or projection.
      injury = player.health&.status
      if injury == "Out"
        puts "[SKIP gather_inputs] #{player.name} – status: OUT"
        return nil
      end

      # Last 5 game logs for current season
      bs = player.box_scores
                .joins(:game)
                .where(games: { season_id: @season.id })
                .where.not(minutes_played: [nil, ""])
                .order("games.date DESC").limit(5)

      if bs.blank?
        puts "[SKIP gather_inputs] #{player.name} – no recent box scores"
        return nil
      end

      minutes_avg = avg_minutes(bs)

      # Skip if player doesn't average at least 15 minutes per game over last 5
      if minutes_avg < 15
        puts "[SKIP gather_inputs] #{player.name} – avg minutes #{minutes_avg.round(1)} < 15"
        return nil
      end

      usage_avg = bs.average(:usage_pct).to_f

      # Adjust expected minutes for minor injuries
      minutes_expected =
        case injury
        when "Day-To-Day" then (minutes_avg * 0.9).round(1)
        when "Healthy", nil then minutes_avg.round(1)
        else minutes_avg.round(1)
        end

      # Final safety: if expected minutes 0 or nil, skip projection
      if minutes_expected <= 0
        puts "[SKIP gather_inputs] #{player.name} – expected minutes #{minutes_expected} <= 0"
        return nil
      end

      # Opponent Defense vs Position multipliers (fallback 1.0)
      dvp = opponent.defense_data_for(@season) || {}
      groups = position_buckets(player.position)
      slice = dvp.slice(*groups).values
      pts_mult = avg_of(slice.map { |h| h["points_multiplier"] }) || 1.0
      reb_mult = avg_of(slice.map { |h| h["rebounds_multiplier"] }) || 1.0
      ast_mult = avg_of(slice.map { |h| h["assists_multiplier"] }) || 1.0

      {
        player: player,
        position: player.position,
        injury_status: injury,
        expected_minutes: minutes_expected,
        usage_pct: usage_avg,

        # Last-5 per-game baselines from BoxScore
        baseline: {
          points:        avg_stat(bs, :points),
          rebounds:      avg_stat(bs, :total_rebounds),
          assists:       avg_stat(bs, :assists),
          threes:        avg_stat(bs, :three_point_field_goals),
          steals:        avg_stat(bs, :steals),
          blocks:        avg_stat(bs, :blocks),
          turnovers:     avg_stat(bs, :turnovers),
          plus_minus:    avg_stat(bs, :plus_minus),
          minutes:       minutes_avg,
          assist_pct:    avg_stat(bs, :assist_pct),
          rebound_pct:   avg_stat(bs, :total_rebound_pct)
        },

        dvp_pts_mult: pts_mult,
        dvp_reb_mult: reb_mult,
        dvp_ast_mult: ast_mult
      }
    end


    def team_injury_boost(player)
      teammates = Player.where(team_id: player.team_id).where.not(id: player.id)
                        .joins(:health) # join the health table
                        .where(healths: { status: ["Day-To-Day", "Out"] }) # note: plural table name

      return 1.0 if teammates.blank?

      pos_relations = {
        "PG" => %w[PG SG],
        "SG" => %w[SG PG],
        "SF" => %w[SF PF],
        "PF" => %w[PF SF C],
        "C"  => %w[C PF]
      }

      relevant_positions = pos_relations[player.position] || []
      boost_factor = 1.0

      teammates.each do |tm|
        next unless relevant_positions.include?(tm.position)
        case tm.health&.status
        when "Out"
          boost_factor += 0.10 # moderate bump
        when "Day-To-Day"
          boost_factor += 0.05 # minor bump
        end
      end

      boost_factor.clamp(1.0, 1.25)
    end

    def project_stats(inputs)
      b = inputs[:baseline]

      # --- Minute & usage scaling ---
      min_factor = b[:minutes].to_f > 0 ? (inputs[:expected_minutes].to_f / b[:minutes].to_f) : 1.0

      # Normalize usage to 0–1 scale
      player_usage = inputs[:usage_pct].to_f
      player_usage /= 100 if player_usage > 1.0

      team_usage = team_usage_anchor(inputs[:player]).to_f
      team_usage /= 100 if team_usage > 1.0

      # Limit usage impact to ±25%
      usage_diff   = player_usage - team_usage
      usage_factor = 1.0 + (usage_diff / team_usage * 0.25).clamp(-0.25, 0.25)

      # Combine scaling
      scale = min_factor * usage_factor

      # --- Rebound & assist efficiency ---
      player_stat = inputs[:player].player_stats.find_by(season_id: @season.id)
      rebound_pct = player_stat&.total_rebound_pct.to_f / 100.0
      assist_pct  = player_stat&.assist_pct.to_f / 100.0

      # If we have recent game data, replace with last-5 averages
      if b[:assist_pct].present? && b[:rebound_pct].present?
        assist_pct  = b[:assist_pct].to_f / 100.0
        rebound_pct = b[:rebound_pct].to_f / 100.0
      end

      team_reb_anchor = 0.15
      team_ast_anchor = 0.12

      reb_eff = (rebound_pct / team_reb_anchor).clamp(0.6, 1.6)
      ast_eff = (assist_pct  / team_ast_anchor).clamp(0.6, 1.6)

      # --- Global shrink factor ---
      shrink = 0.60

      # --- Add random noise factors ---
      # Slight variability: ±10% for core stats, ±5% for peripherals
      rand_core = -> { 1.0 + rand(-0.10..0.10) }
      rand_side = -> { 1.0 + rand(-0.05..0.05) }

      outputs = {
        points:     b[:points]   * scale * inputs[:dvp_pts_mult] * shrink * rand_core.call,
        rebounds:   b[:rebounds] * min_factor * reb_eff * inputs[:dvp_reb_mult] * shrink * rand_core.call,
        assists:    b[:assists]  * min_factor * ast_eff * inputs[:dvp_ast_mult] * shrink * rand_core.call,
        threes:     b[:threes]   * scale * shrink * rand_side.call,
        steals:     b[:steals]   * min_factor * shrink * rand_side.call,
        blocks:     b[:blocks]   * min_factor * shrink * rand_side.call,
        turnovers:  b[:turnovers]* scale * shrink * rand_side.call,
        plus_minus: b[:plus_minus]* min_factor * shrink * rand_side.call,

        # include projected assist% and rebound%
        assist_pct:  assist_pct * 100,   # convert back to 0–100 scale
        rebound_pct: rebound_pct * 100
      }

      # --- Injury/team context boost ---
      boost = team_injury_boost(inputs[:player])

      # --- Cap extreme outliers and apply boost ---
      max_baseline = b.values.compact.max.to_f
      outputs.transform_values! do |v|
        (v * boost).clamp(0, max_baseline * 2.0).round(2)
      end

      outputs
    end


    # ── helpers ───────────────────────────────────────────

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

    # Anchor usage to team mean ~20% to keep relative scaling reasonable.
    def team_usage_anchor(player)
      team_ps = PlayerStat.joins(:player)
                          .where(players: { team_id: player.team_id }, season_id: @season.id)
                          .average(:usage_pct).to_f
      team_ps.positive? ? team_ps : 20.0
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
