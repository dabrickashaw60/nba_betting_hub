# app/services/simulations/game_simulator.rb
require "zlib"
require "json"

module Simulations
  class GameSimulator
    MODEL_VERSION = "sim_v1_from_projections".freeze

    # ------------------------------------------------------------
    # Core idea:
    # Anchor the final team points to the sum of player projections,
    # and only let pace/ORtg/DRtg "nudge" the outcome.
    #
    # target_points = PLAYER_POINTS_WEIGHT * player_sum_points
    #              + ENV_POINTS_WEIGHT    * (possessions * ppp)
    # ------------------------------------------------------------
    PLAYER_POINTS_WEIGHT = 0.55
    ENV_POINTS_WEIGHT    = 0.45

    # Blend offense + defense vs league average PPP (derived from TeamAdvancedStat league avg ORtg)
    OFF_WEIGHT = 0.60
    DEF_WEIGHT = 0.40

    # Monte Carlo defaults
    DEFAULT_SIMS = 10000

    # Randomness knobs (tune later)
    POSS_SD = 4.0        # possessions std dev
    PPP_SD  = 0.032      # points-per-possession std dev (team-level)

    # Small home boost (optional)
    HOME_PPP_BONUS = 0.010

    # Hard clamps to prevent absurd outcomes
    POSS_MIN = 90.0
    POSS_MAX = 110.0
    PPP_MIN  = 0.95
    PPP_MAX  = 1.30

    MC_POINTS_SD = 10.0

    # If you want pure deterministic output, keep noise off
    DEFAULT_POINTS_SD = 0.0

    def initialize(date:, season: nil)
      @date = date
      @season = season || Season.find_by(current: true)
      raise "No season" unless @season

      # Computes league averages from TeamAdvancedStat for this season
      @league = Simulations::LeagueContext.new(season: @season)
    end

    # ------------------------------------------------------------------
    # CACHED SINGLE SIM (deterministic unless you turn on noise)
    # ------------------------------------------------------------------
    def fetch_or_simulate!(game_id:, add_noise: false, points_sd: DEFAULT_POINTS_SD)
      existing = GameSimulation.find_by(
        date: @date,
        game_id: game_id,
        model_version: MODEL_VERSION
      )
      return existing_payload(existing) if existing.present?

      simulate_game!(game_id: game_id, add_noise: add_noise, points_sd: points_sd, persist: true)
    end

    # Public: simulate a single game “mean” outcome, reconcile players to totals.
    # Returns a hash payload (and persists a GameSimulation row when persist: true).
    def simulate_game!(game_id:, add_noise: false, points_sd: DEFAULT_POINTS_SD, persist: true)
      game = Game.includes(:home_team, :visitor_team).find(game_id)

      home_team    = game.home_team
      visitor_team = game.visitor_team

      home_rows    = projections_for(team: home_team, opponent: visitor_team)
      visitor_rows = projections_for(team: visitor_team, opponent: home_team)

      home_base    = sum_team(home_rows)    # includes baseline player points sum
      visitor_base = sum_team(visitor_rows)

      poss_mean = expected_possessions(home_team, visitor_team)

      home_ppp_mean    = expected_ppp(home_team, visitor_team) + HOME_PPP_BONUS
      visitor_ppp_mean = expected_ppp(visitor_team, home_team)

      # Environment points (pace + ppp)
      home_env_points    = poss_mean * home_ppp_mean
      visitor_env_points = poss_mean * visitor_ppp_mean

      # Player-anchored blended target points
      home_target_points = blended_points(player_points: home_base[:points], env_points: home_env_points)
      visitor_target_points = blended_points(player_points: visitor_base[:points], env_points: visitor_env_points)

      # Optional extra points noise (rarely needed once you MC)
      if add_noise && points_sd.to_f > 0.0
        home_target_points += normal_noise(sd: points_sd, seed: seed_for(game.id, home_team.id, "pts"))
        visitor_target_points += normal_noise(sd: points_sd, seed: seed_for(game.id, visitor_team.id, "pts"))
      end

      home_target_points    = [home_target_points, 0.0].max
      visitor_target_points = [visitor_target_points, 0.0].max

      # Reconcile player outputs to final team totals (points drive the scale)
      home_scale    = safe_scale(target: home_target_points, baseline: home_base[:points])
      visitor_scale = safe_scale(target: visitor_target_points, baseline: visitor_base[:points])

      home_scaled_rows    = scale_players(home_rows, scale: home_scale)
      visitor_scaled_rows = scale_players(visitor_rows, scale: visitor_scale)

      home_totals    = sum_scaled_team(home_scaled_rows)
      visitor_totals = sum_scaled_team(visitor_scaled_rows)

      payload = {
        date: @date,
        season_id: @season.id,
        game_id: game.id,
        model_version: MODEL_VERSION,

        home_team_id: home_team.id,
        visitor_team_id: visitor_team.id,

        league: league_payload,
        env: {
          possessions_mean: poss_mean,
          home_ppp_mean: home_ppp_mean,
          visitor_ppp_mean: visitor_ppp_mean,
          home_env_points: home_env_points,
          visitor_env_points: visitor_env_points,
          blend: {
            player_weight: PLAYER_POINTS_WEIGHT,
            env_weight: ENV_POINTS_WEIGHT
          }
        },

        home_baseline: home_base,
        visitor_baseline: visitor_base,

        home_scale: home_scale,
        visitor_scale: visitor_scale,

        home_totals: home_totals,
        visitor_totals: visitor_totals,

        home_players: home_scaled_rows,
        visitor_players: visitor_scaled_rows
      }

      save_single_simulation!(payload) if persist
      payload
    end

    # Public: simulate all games for a date (single sim per game)
    def simulate_date!(add_noise: false, points_sd: DEFAULT_POINTS_SD, persist: true)
      game_ids = Game.where(date: @date, season_id: @season.id).pluck(:id)
      game_ids.map do |gid|
        simulate_game!(game_id: gid, add_noise: add_noise, points_sd: points_sd, persist: persist)
      end
    end

    # ------------------------------------------------------------------
    # MONTE CARLO DISTRIBUTION (win%, spread/total percentiles)
    #
    # Key change:
    # Each sim draws possessions + PPP noise to get env_points,
    # then BLENDS env_points with the fixed baseline player points sum
    # to anchor totals to your player model.
    # ------------------------------------------------------------------
    def fetch_or_simulate_distribution!(game_id:, sims: DEFAULT_SIMS, debug: false, debug_samples: 25, force: false)
      model = distribution_model_version

      if !force
        existing = GameSimulation.find_by(date: @date, game_id: game_id, model_version: model)
        return existing if existing.present?
      end

      simulate_game_distribution!(
        game_id: game_id,
        sims: sims,
        persist: true,
        debug: debug,
        debug_samples: debug_samples
      )

      GameSimulation.find_by(date: @date, game_id: game_id, model_version: model)
    end


    def simulate_game_distribution!(game_id:, sims: DEFAULT_SIMS, persist: true, debug: false, debug_samples: 25)
      game = Game.includes(:home_team, :visitor_team).find(game_id)

      home_team    = game.home_team
      visitor_team = game.visitor_team

      home_rows    = projections_for(team: home_team, opponent: visitor_team)
      visitor_rows = projections_for(team: visitor_team, opponent: home_team)

      home_base    = sum_team(home_rows)
      visitor_base = sum_team(visitor_rows)

      poss_mean = expected_possessions(home_team, visitor_team)

      home_ppp_mean    = expected_ppp(home_team, visitor_team) + HOME_PPP_BONUS
      visitor_ppp_mean = expected_ppp(visitor_team, home_team)

      spreads = []
      totals  = []
      home_pts_arr = []
      vis_pts_arr  = []
      home_wins = 0

      sims_i = sims.to_i
      debug_rows = []

      sims_i.times do |i|
        poss = poss_mean + normal_noise(sd: POSS_SD, seed: seed_for(game.id, 0, "poss-#{i}"))
        poss = [[poss, POSS_MIN].max, POSS_MAX].min

        hppp = home_ppp_mean + normal_noise(sd: PPP_SD, seed: seed_for(game.id, home_team.id, "hppp-#{i}"))
        vppp = visitor_ppp_mean + normal_noise(sd: PPP_SD, seed: seed_for(game.id, visitor_team.id, "vppp-#{i}"))

        hppp = [[hppp, PPP_MIN].max, PPP_MAX].min
        vppp = [[vppp, PPP_MIN].max, PPP_MAX].min

        # Environment points for this sim
        home_env = poss * hppp
        vis_env  = poss * vppp

        # Anchor to player sums
        hpts = blended_points(player_points: home_base[:points], env_points: home_env)
        vpts = blended_points(player_points: visitor_base[:points], env_points: vis_env)

        if MC_POINTS_SD.to_f > 0.0
          hpts += normal_noise(sd: MC_POINTS_SD, seed: seed_for(game.id, home_team.id, "mc-hpts-#{i}"))
          vpts += normal_noise(sd: MC_POINTS_SD, seed: seed_for(game.id, visitor_team.id, "mc-vpts-#{i}"))
        end

        if debug && debug_rows.size < debug_samples
          debug_rows << {
            i: i + 1,
            poss: poss,
            hppp: hppp,
            vppp: vppp,
            home_env: home_env,
            vis_env: vis_env,
            home_points: hpts,
            visitor_points: vpts,
            spread: (hpts - vpts),
            total: (hpts + vpts)
          }
        end

        home_wins += 1 if hpts > vpts

        home_pts_arr << hpts
        vis_pts_arr  << vpts
        spreads << (hpts - vpts)   # home - visitor
        totals  << (hpts + vpts)
      end

      home_points_sd   = stddev(home_pts_arr)
      visitor_points_sd = stddev(vis_pts_arr)
      spread_sd        = stddev(spreads)
      total_sd         = stddev(totals)


      out = {
        home_points_mean: mean(home_pts_arr),
        home_points_sd: home_points_sd,

        visitor_points_mean: mean(vis_pts_arr),
        visitor_points_sd: visitor_points_sd,

        win_prob_home: (home_wins.to_f / sims_i.to_f),

        spread_mean: mean(spreads),
        spread_sd: spread_sd,
        spread_p10: percentile(spreads, 0.10),
        spread_p50: percentile(spreads, 0.50),
        spread_p90: percentile(spreads, 0.90),

        total_mean: mean(totals),
        total_sd: total_sd,
        total_p10: percentile(totals, 0.10),
        total_p50: percentile(totals, 0.50),
        total_p90: percentile(totals, 0.90)
      }


      payload = {
        date: @date,
        season_id: @season.id,
        game_id: game.id,
        model_version: distribution_model_version,
        sims_count: sims_i,

        home_team_id: home_team.id,
        visitor_team_id: visitor_team.id,

        league: league_payload,
        env: {
          possessions_mean: poss_mean,
          possessions_sd: POSS_SD,
          home_ppp_mean: home_ppp_mean,
          visitor_ppp_mean: visitor_ppp_mean,
          ppp_sd: PPP_SD,
          mc_points_sd: MC_POINTS_SD,
          blend: {
            player_weight: PLAYER_POINTS_WEIGHT,
            env_weight: ENV_POINTS_WEIGHT
          }
        },

        home_baseline: home_base,
        visitor_baseline: visitor_base,

        outputs: out,

        debug: debug,
        debug_samples: (debug ? debug_rows : nil)

      }

      save_distribution!(payload) if persist
      payload
    end

    private

    # -------------------------
    # Blending / anchoring
    # -------------------------
    def blended_points(player_points:, env_points:)
      pp = player_points.to_f
      ep = env_points.to_f
      (PLAYER_POINTS_WEIGHT * pp) + (ENV_POINTS_WEIGHT * ep)
    end

    # -------------------------
    # Projections
    # -------------------------
    def projections_for(team:, opponent:)
      rows = Projection.where(date: @date, team_id: team.id, opponent_team_id: opponent.id)
      raise "No projections for team #{team.id} vs #{opponent.id} on #{@date}" if rows.blank?
      rows
    end

    # -------------------------
    # Advanced stats helpers
    # -------------------------
    def team_adv(team)
      TeamAdvancedStat.find_by(team_id: team.id, season_id: @season.id)&.stats || {}
    end

    def pace_for(team)
      v = team_adv(team)["pace"].to_f
      v > 0 ? v : @league.pace_avg
    end

    def off_ppp_for(team)
      v = team_adv(team)["off_rtg"].to_f
      v = @league.off_rtg_avg if v <= 0
      v / 100.0
    end

    def def_ppp_for(team)
      v = team_adv(team)["def_rtg"].to_f
      v = @league.def_rtg_avg if v <= 0
      v / 100.0
    end

    def expected_possessions(home_team, visitor_team)
      (pace_for(home_team) + pace_for(visitor_team)) / 2.0
    end

    def expected_ppp(team, opponent)
      team_off = off_ppp_for(team)
      opp_def  = def_ppp_for(opponent)
      lg       = @league.ppp_avg

      lg + OFF_WEIGHT * (team_off - lg) - DEF_WEIGHT * (opp_def - lg)
    end

    def league_payload
      {
        pace_avg: @league.pace_avg,
        off_rtg_avg: @league.off_rtg_avg,
        def_rtg_avg: @league.def_rtg_avg,
        ppp_avg: @league.ppp_avg
      }
    end

    # -------------------------
    # Summation
    # -------------------------
    def sum_team(rows)
      {
        minutes: rows.sum(:expected_minutes).to_f,
        points: rows.sum(:proj_points).to_f,
        rebounds: rows.sum(:proj_rebounds).to_f,
        assists: rows.sum(:proj_assists).to_f,
        threes: rows.sum(:proj_threes).to_f
      }
    end

    def sum_scaled_team(rows)
      {
        minutes: rows.sum { |r| r[:minutes].to_f },
        points: rows.sum { |r| r[:points].to_f },
        rebounds: rows.sum { |r| r[:rebounds].to_f },
        assists: rows.sum { |r| r[:assists].to_f },
        threes: rows.sum { |r| r[:threes].to_f }
      }
    end

    # -------------------------
    # Player scaling (reconcile to team totals)
    # -------------------------
    def safe_scale(target:, baseline:)
      b = baseline.to_f
      return 1.0 if b <= 0.0
      (target.to_f / b)
    end

    def scale_players(scope, scale:)
      s = scale.to_f
      scope.includes(:player).map do |p|
        {
          player_id: p.player_id,
          name: p.player&.name,
          team_id: p.team_id,
          opponent_team_id: p.opponent_team_id,
          position: p.position,

          minutes: p.expected_minutes.to_f,
          points: p.proj_points.to_f * s,
          rebounds: p.proj_rebounds.to_f * s,
          assists: p.proj_assists.to_f * s,
          threes: p.proj_threes.to_f * s
        }
      end
    end

    def save_single_simulation!(payload)
      gs = GameSimulation.find_or_initialize_by(
        date: payload[:date],
        game_id: payload[:game_id],
        model_version: payload[:model_version]
      )

      meta_hash = {
        league: payload[:league],
        env: payload[:env],
        home_minutes: payload[:home_baseline][:minutes],
        visitor_minutes: payload[:visitor_baseline][:minutes],
        debug: payload[:debug],
        debug_samples: payload[:debug_samples]        
      }

      gs.assign_attributes(
        season_id: payload[:season_id],
        home_team_id: payload[:home_team_id],
        visitor_team_id: payload[:visitor_team_id],
        sims_count: 1,

        home_points: payload[:home_totals][:points].round,
        visitor_points: payload[:visitor_totals][:points].round,
        home_rebounds: payload[:home_totals][:rebounds],
        visitor_rebounds: payload[:visitor_totals][:rebounds],
        home_assists: payload[:home_totals][:assists],
        visitor_assists: payload[:visitor_totals][:assists],
        home_threes: payload[:home_totals][:threes],
        visitor_threes: payload[:visitor_totals][:threes],

        home_baseline_points: payload[:home_baseline][:points],
        visitor_baseline_points: payload[:visitor_baseline][:points],
        home_baseline_rebounds: payload[:home_baseline][:rebounds],
        visitor_baseline_rebounds: payload[:visitor_baseline][:rebounds],
        home_baseline_assists: payload[:home_baseline][:assists],
        visitor_baseline_assists: payload[:visitor_baseline][:assists],
        home_baseline_threes: payload[:home_baseline][:threes],
        visitor_baseline_threes: payload[:visitor_baseline][:threes],

        home_scale: payload[:home_scale],
        visitor_scale: payload[:visitor_scale],

        meta: meta_hash
      )

      gs.save!
      gs
    end

    def save_distribution!(payload)
      out = payload[:outputs]

      meta_hash = {
        league: payload[:league],
        env: payload[:env],
        outputs: payload[:outputs]
      }

      gs = GameSimulation.find_or_initialize_by(
        date: payload[:date],
        game_id: payload[:game_id],
        model_version: payload[:model_version]
      )

      gs.assign_attributes(
        season_id: payload[:season_id],
        home_team_id: payload[:home_team_id],
        visitor_team_id: payload[:visitor_team_id],
        sims_count: payload[:sims_count],

        home_points: out[:home_points_mean].round,
        visitor_points: out[:visitor_points_mean].round,

        home_baseline_points: payload[:home_baseline][:points],
        visitor_baseline_points: payload[:visitor_baseline][:points],
        home_baseline_rebounds: payload[:home_baseline][:rebounds],
        visitor_baseline_rebounds: payload[:visitor_baseline][:rebounds],
        home_baseline_assists: payload[:home_baseline][:assists],
        visitor_baseline_assists: payload[:visitor_baseline][:assists],
        home_baseline_threes: payload[:home_baseline][:threes],
        visitor_baseline_threes: payload[:visitor_baseline][:threes],

        home_rebounds: payload[:home_baseline][:rebounds],
        visitor_rebounds: payload[:visitor_baseline][:rebounds],
        home_assists: payload[:home_baseline][:assists],
        visitor_assists: payload[:visitor_baseline][:assists],
        home_threes: payload[:home_baseline][:threes],
        visitor_threes: payload[:visitor_baseline][:threes],

        home_scale: 1.0,
        visitor_scale: 1.0,

        meta: meta_hash
      )

      gs.save!
      gs
    end

    def distribution_model_version
      "#{MODEL_VERSION}_mc_v1"
    end

    def existing_payload(gs)
      meta_hash =
        case gs.meta
        when Hash
          gs.meta
        when String
          begin
            JSON.parse(gs.meta)
          rescue
            {}
          end
        else
          {}
        end

      {
        date: gs.date,
        game_id: gs.game_id,
        model_version: gs.model_version,
        sims_count: gs.sims_count,

        home_totals: {
          points: gs.home_points,
          rebounds: gs.home_rebounds,
          assists: gs.home_assists,
          threes: gs.home_threes,
          minutes: meta_hash["home_minutes"]
        },
        visitor_totals: {
          points: gs.visitor_points,
          rebounds: gs.visitor_rebounds,
          assists: gs.visitor_assists,
          threes: gs.visitor_threes,
          minutes: meta_hash["visitor_minutes"]
        },

        home_scale: gs.home_scale,
        visitor_scale: gs.visitor_scale,
        meta: meta_hash
      }
    end


    # -------------------------
    # Math helpers
    # -------------------------
    def mean(arr)
      return 0.0 if arr.blank?
      arr.sum.to_f / arr.size.to_f
    end

    def percentile(arr, p)
      return 0.0 if arr.blank?
      a = arr.sort
      idx = (p.to_f * (a.size - 1)).round
      a[idx].to_f
    end

    def stddev(arr)
      return 0.0 if arr.blank? || arr.size < 2
      m = mean(arr)
      var = arr.sum { |x| (x.to_f - m) ** 2 } / (arr.size - 1).to_f
      Math.sqrt(var)
    end

    # Deterministic normal noise using Box-Muller
    def normal_noise(sd:, seed:)
      rng = Random.new(seed)
      u1 = [rng.rand, 1e-12].max
      u2 = rng.rand
      z0 = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      z0 * sd.to_f
    end

    def seed_for(game_id, team_id, tag)
      Zlib.crc32("#{@date}-#{MODEL_VERSION}-#{game_id}-#{team_id}-#{tag}")
    end

    def symbolize_keys_deep(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = symbolize_keys_deep(v)
        end
      when Array
        obj.map { |v| symbolize_keys_deep(v) }
      else
        obj
      end
    end
  end
end
