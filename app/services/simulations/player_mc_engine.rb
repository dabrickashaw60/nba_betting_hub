# app/services/simulations/player_mc_engine.rb
require "zlib"

module Simulations
  class PlayerMcEngine
    TEAM_MINUTES_TARGET = 240.0

    # Minutes noise
    MIN_SD_BASE = 2.5
    MIN_SD_PCT  = 0.12

    # Correlation
    TEAM_PERF_SD   = 0.10
    PLAYER_PERF_SD = 0.18

    # Pct swings
    USG_SD     = 2.0
    REB_PCT_SD = 1.5
    AST_PCT_SD = 1.8

    # Sensitivities
    USG_POINTS_SENS = 0.25
    USG_3S_SENS     = 0.25
    REB_SENS        = 0.25
    AST_SENS        = 0.20

    # Stat noise scales
    PTS_NOISE_K = 0.90
    REB_NOISE_K = 0.70
    AST_NOISE_K = 0.70
    THR_NOISE_K = 0.60

    def initialize(date:, model_version:)
      @date = date
      @model_version = model_version
    end

    # team_rows: ActiveRecord relation or array of Projection rows
    # returns array of hashes (one per player) with simulated stat line
    def simulate_team_players_once(team_rows, game_id:, team_id:, iter_tag:)
      rows = team_rows.to_a

      # 1) sample minutes
      mins = {}
      rows.each do |p|
        mu = p.expected_minutes.to_f
        sd = [MIN_SD_BASE, mu * MIN_SD_PCT].max
        m  = mu + normal_noise(sd: sd, seed: seed_for(game_id, p.player_id, "#{iter_tag}-min"))
        mins[p.player_id] = clamp_range(m, 0.0, 42.0)
      end

      # 2) normalize minutes to 240
      mins = renormalize_hash_to_total(mins, TEAM_MINUTES_TARGET)

      # 3) shared team factor
      team_perf = normal_noise(sd: TEAM_PERF_SD, seed: seed_for(game_id, team_id, "#{iter_tag}-teamperf"))

      out = []

      rows.each do |p|
        pid   = p.player_id
        exp_m = p.expected_minutes.to_f
        sim_m = mins[pid].to_f

        min_factor = exp_m > 0.5 ? (sim_m / exp_m) : 0.0

        # pct baselines
        usg0 = p.usage_pct.to_f
        reb0 = p.rebound_pct.to_f
        ast0 = p.assist_pct.to_f

        # pct draws
        usg = clamp_range(usg0 + normal_noise(sd: USG_SD, seed: seed_for(game_id, pid, "#{iter_tag}-usg")), 5.0, 45.0)
        reb = clamp_range(reb0 + normal_noise(sd: REB_PCT_SD, seed: seed_for(game_id, pid, "#{iter_tag}-trb")), 0.0, 30.0)
        ast = clamp_range(ast0 + normal_noise(sd: AST_PCT_SD, seed: seed_for(game_id, pid, "#{iter_tag}-ast")), 0.0, 60.0)

        # shared player factor
        player_perf = normal_noise(sd: PLAYER_PERF_SD, seed: seed_for(game_id, pid, "#{iter_tag}-pperf"))

        perf_mult = Math.exp(team_perf + player_perf)

        usg_mult_pts = 1.0 + ((usg - usg0) / 100.0) * USG_POINTS_SENS
        usg_mult_3s  = 1.0 + ((usg - usg0) / 100.0) * USG_3S_SENS
        reb_mult     = 1.0 + ((reb - reb0) / 100.0) * REB_SENS
        ast_mult     = 1.0 + ((ast - ast0) / 100.0) * AST_SENS

        # baseline means scaled
        pts_mu = p.proj_points.to_f   * min_factor * usg_mult_pts * perf_mult
        reb_mu = p.proj_rebounds.to_f * min_factor * reb_mult     * perf_mult
        ast_mu = p.proj_assists.to_f  * min_factor * ast_mult     * perf_mult
        thr_mu = p.proj_threes.to_f   * min_factor * usg_mult_3s  * perf_mult

        # stat noise around mean
        pts  = pts_mu + normal_noise(sd: PTS_NOISE_K * Math.sqrt([pts_mu, 0.5].max), seed: seed_for(game_id, pid, "#{iter_tag}-pts"))
        rebv = reb_mu + normal_noise(sd: REB_NOISE_K * Math.sqrt([reb_mu, 0.5].max), seed: seed_for(game_id, pid, "#{iter_tag}-reb"))
        astv = ast_mu + normal_noise(sd: AST_NOISE_K * Math.sqrt([ast_mu, 0.5].max), seed: seed_for(game_id, pid, "#{iter_tag}-aststat"))
        thr  = thr_mu + normal_noise(sd: THR_NOISE_K * Math.sqrt([thr_mu, 0.5].max), seed: seed_for(game_id, pid, "#{iter_tag}-thr"))

        # clamps
        pts  = [pts, 0.0].max
        rebv = [rebv, 0.0].max
        astv = [astv, 0.0].max
        thr  = [thr, 0.0].max

        # sanity cap
        pts_cap = sim_m * 1.25
        pts = [pts, pts_cap].min

        out << {
          player_id: pid,
          minutes: sim_m,
          points: pts,
          rebounds: rebv,
          assists: astv,
          threes: thr,
          usage_pct: usg,
          rebound_pct: reb,
          assist_pct: ast
        }
      end

      out
    end

    # ---------- helpers ----------

    def renormalize_hash_to_total(h, target_total)
      total = h.values.sum.to_f
      return h if total <= 0.0
      factor = target_total.to_f / total
      h.transform_values { |v| v.to_f * factor }
    end

    def clamp_range(v, lo, hi)
      [[v.to_f, lo].max, hi].min
    end

    # Deterministic normal noise using Box-Muller
    def normal_noise(sd:, seed:)
      rng = Random.new(seed)
      u1 = [rng.rand, 1e-12].max
      u2 = rng.rand
      z0 = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      z0 * sd.to_f
    end

    def seed_for(game_id, entity_id, tag)
      Zlib.crc32("#{@date}-#{@model_version}-#{game_id}-#{entity_id}-#{tag}")
    end
  end
end
