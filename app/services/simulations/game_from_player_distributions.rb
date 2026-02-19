module Simulations
  class GameFromPlayerDistributions
    MODEL_VERSION = "game_from_player_mc_means_v1".freeze

    def initialize(date:, season: nil, player_model_version: "proj_mc_v1")
      @date = date
      @season = season || Season.find_by(current: true)
      raise "No season" unless @season
      @player_model_version = player_model_version
    end

    def build!(game_id:, sims: 500, persist: true)
      game = Game.includes(:home_team, :visitor_team).find(game_id)

      home_players = player_rows(game.home_team_id, game.visitor_team_id)
      vis_players  = player_rows(game.visitor_team_id, game.home_team_id)

      sims_i = sims.to_i
      home_pts = []
      vis_pts  = []
      spreads  = []
      totals   = []
      home_wins = 0

      sims_i.times do |i|
        h = simulate_team_points(home_players, seed_base: "#{game.id}-home-#{i}")
        v = simulate_team_points(vis_players,  seed_base: "#{game.id}-vis-#{i}")

        home_pts << h
        vis_pts  << v
        spreads << (h - v)
        totals  << (h + v)
        home_wins += 1 if h > v
      end

      payload = {
        date: @date,
        season_id: @season.id,
        game_id: game.id,
        model_version: MODEL_VERSION,
        sims_count: sims_i,

        home_team_id: game.home_team_id,
        visitor_team_id: game.visitor_team_id,

        home_points_mean: mean(home_pts),
        visitor_points_mean: mean(vis_pts),
        home_points_sd: stddev(home_pts),
        visitor_points_sd: stddev(vis_pts),

        win_prob_home: home_wins.to_f / sims_i.to_f,

        spread_mean: mean(spreads),
        spread_sd: stddev(spreads),
        spread_p10: percentile(spreads, 0.10),
        spread_p50: percentile(spreads, 0.50),
        spread_p90: percentile(spreads, 0.90),

        total_mean: mean(totals),
        total_sd: stddev(totals),
        total_p10: percentile(totals, 0.10),
        total_p50: percentile(totals, 0.50),
        total_p90: percentile(totals, 0.90),

        source_player_model_version: @player_model_version
      }

      save_distribution!(payload) if persist
      payload
    end


    private

    def team_totals(team_id, opp_id)
      rows = ProjectionDistribution.where(
        date: @date,
        team_id: team_id,
        opponent_team_id: opp_id,
        model_version: @player_model_version
      )

      raise "No ProjectionDistribution rows for team #{team_id} vs #{opp_id} on #{@date}" if rows.blank?

      {
        sims_count: rows.first.sims_count.to_i,
        points_mean: rows.sum(:points_mean).to_f,
        points_sd_sum: rows.sum(:points_sd).to_f
      }
    end

    def save!(payload)
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

        home_points: payload[:home_points_mean].round,
        visitor_points: payload[:visitor_points_mean].round,

        home_baseline_points: payload[:home_points_mean],
        visitor_baseline_points: payload[:visitor_points_mean],

        home_scale: 1.0,
        visitor_scale: 1.0,

        meta: {
          source_player_model_version: @player_model_version,
          home_points_sd_sum: payload[:home_points_sd],
          visitor_points_sd_sum: payload[:visitor_points_sd],
          spread_mean: payload[:spread_mean],
          total_mean: payload[:total_mean]
        }
      )

      gs.save!
    end

    def player_rows(team_id, opp_id)
      rows = ProjectionDistribution.where(
        date: @date,
        team_id: team_id,
        opponent_team_id: opp_id,
        model_version: @player_model_version
      )
      raise "No ProjectionDistribution rows for team #{team_id} vs #{opp_id} on #{@date}" if rows.blank?
      rows
    end

    def simulate_team_points(rows, seed_base:)
      rng = Random.new(Zlib.crc32("#{@date}-#{seed_base}-#{MODEL_VERSION}"))
      sum = 0.0

      rows.each do |r|
        mu = r.points_mean.to_f
        sd = r.points_sd.to_f

        # sample normal via Box-Muller
        u1 = [rng.rand, 1e-12].max
        u2 = rng.rand
        z0 = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)

        x = mu + z0 * sd
        x = 0.0 if x.nan? || x.infinite? || x < 0.0
        sum += x
      end

      sum
    end

    def save_distribution!(payload)
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

        home_points: payload[:home_points_mean].round,
        visitor_points: payload[:visitor_points_mean].round,

        home_baseline_points: payload[:home_points_mean],
        visitor_baseline_points: payload[:visitor_points_mean],

        home_scale: 1.0,
        visitor_scale: 1.0,

        meta: {
          source_player_model_version: payload[:source_player_model_version],
          outputs: {
            home_points_mean: payload[:home_points_mean],
            home_points_sd: payload[:home_points_sd],
            visitor_points_mean: payload[:visitor_points_mean],
            visitor_points_sd: payload[:visitor_points_sd],
            win_prob_home: payload[:win_prob_home],
            spread_mean: payload[:spread_mean],
            spread_sd: payload[:spread_sd],
            spread_p10: payload[:spread_p10],
            spread_p50: payload[:spread_p50],
            spread_p90: payload[:spread_p90],
            total_mean: payload[:total_mean],
            total_sd: payload[:total_sd],
            total_p10: payload[:total_p10],
            total_p50: payload[:total_p50],
            total_p90: payload[:total_p90]
          }
        }
      )

      gs.save!
    end

    def mean(arr)
      return 0.0 if arr.blank?
      arr.sum.to_f / arr.size.to_f
    end

    def stddev(arr)
      return 0.0 if arr.blank? || arr.size < 2
      m = mean(arr)
      var = arr.sum { |x| (x.to_f - m) ** 2 } / (arr.size - 1).to_f
      Math.sqrt(var)
    end

    def percentile(arr, p)
      return 0.0 if arr.blank?
      a = arr.sort
      idx = (p.to_f * (a.size - 1)).round
      a[idx].to_f
    end

  end
end
