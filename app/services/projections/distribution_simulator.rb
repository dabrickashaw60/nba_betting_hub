# app/services/projections/distribution_simulator.rb
require "zlib"

module Projections
  class DistributionSimulator
    MODEL_VERSION = "proj_mc_v1".freeze

    def initialize(date:, season: nil, sims: 500, model_version: MODEL_VERSION, force: false)
      @date = date
      @season = season || Season.find_by(current: true)
      raise "No season" unless @season

      @sims = sims.to_i
      @model_version = model_version
      @force = force

      # IMPORTANT:
      # Your player Monte Carlo now lives in Simulations::PlayerMcEngine
      @mc = Simulations::PlayerMcEngine.new(date: @date, model_version: Simulations::GameSimulator::MODEL_VERSION)
    end

    def run!
      games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
      return 0 if games.blank?

      upserts = 0

      games.each do |game|
        [
          [game.home_team, game.visitor_team, game.id, "home"],
          [game.visitor_team, game.home_team, game.id, "vis"]
        ].each do |team, opp, game_id, side_tag|
          rows = Projection.where(date: @date, team_id: team.id, opponent_team_id: opp.id)
          next if rows.blank?

          # If not forcing, skip this matchup if any rows already exist
          if !@force
            any_existing = ProjectionDistribution.where(
              date: @date,
              team_id: team.id,
              opponent_team_id: opp.id,
              model_version: @model_version
            ).exists?
            next if any_existing
          end

          stats = simulate_distribution(
            rows,
            game_id: game_id,
            team_id: team.id,
            iter_prefix: "#{game_id}-#{side_tag}"
          )

          rows.each do |p|
            pid = p.player_id
            s = stats[pid]
            next if s.blank?

            rec = ProjectionDistribution.find_or_initialize_by(
              date: @date,
              player_id: pid,
              model_version: @model_version
            )

            rec.assign_attributes(
              season_id: @season.id,
              team_id: team.id,
              opponent_team_id: opp.id,
              sims_count: @sims,

              minutes_mean: s[:minutes][:mean], minutes_sd: s[:minutes][:sd],
              minutes_p10: s[:minutes][:p10], minutes_p50: s[:minutes][:p50], minutes_p90: s[:minutes][:p90],

              points_mean: s[:points][:mean], points_sd: s[:points][:sd],
              points_p10: s[:points][:p10], points_p50: s[:points][:p50], points_p90: s[:points][:p90],

              rebounds_mean: s[:rebounds][:mean], rebounds_sd: s[:rebounds][:sd],
              rebounds_p10: s[:rebounds][:p10], rebounds_p50: s[:rebounds][:p50], rebounds_p90: s[:rebounds][:p90],

              assists_mean: s[:assists][:mean], assists_sd: s[:assists][:sd],
              assists_p10: s[:assists][:p10], assists_p50: s[:assists][:p50], assists_p90: s[:assists][:p90],

              threes_mean: s[:threes][:mean], threes_sd: s[:threes][:sd],
              threes_p10: s[:threes][:p10], threes_p50: s[:threes][:p50], threes_p90: s[:threes][:p90]
            )

            rec.save!
            upserts += 1
          end
        end
      end

      upserts
    end

    private

    def simulate_distribution(team_rows, game_id:, team_id:, iter_prefix:)
      by_player = Hash.new { |h, k| h[k] = { minutes: [], points: [], rebounds: [], assists: [], threes: [] } }

      @sims.times do |i|
        sim_rows = @mc.simulate_team_players_once(
          team_rows,
          game_id: game_id,
          team_id: team_id,
          iter_tag: "#{iter_prefix}-i#{i}"
        )

        sim_rows.each do |r|
          pid = r[:player_id]
          by_player[pid][:minutes]  << r[:minutes].to_f
          by_player[pid][:points]   << r[:points].to_f
          by_player[pid][:rebounds] << r[:rebounds].to_f
          by_player[pid][:assists]  << r[:assists].to_f
          by_player[pid][:threes]   << r[:threes].to_f
        end
      end

      out = {}
      by_player.each do |pid, h|
        out[pid] = {
          minutes:  summarize(h[:minutes]),
          points:   summarize(h[:points]),
          rebounds: summarize(h[:rebounds]),
          assists:  summarize(h[:assists]),
          threes:   summarize(h[:threes])
        }
      end
      out
    end

    def summarize(arr)
      a = arr.compact.sort
      return { mean: 0.0, sd: 0.0, p10: 0.0, p50: 0.0, p90: 0.0 } if a.empty?

      mean = a.sum.to_f / a.size.to_f
      sd = stddev_sorted(a, mean)

      {
        mean: mean,
        sd: sd,
        p10: percentile_sorted(a, 0.10),
        p50: percentile_sorted(a, 0.50),
        p90: percentile_sorted(a, 0.90)
      }
    end

    def percentile_sorted(sorted_arr, p)
      return 0.0 if sorted_arr.empty?
      idx = (p.to_f * (sorted_arr.size - 1)).round
      sorted_arr[idx].to_f
    end

    def stddev_sorted(sorted_arr, mean)
      return 0.0 if sorted_arr.size < 2
      var = sorted_arr.sum { |x| (x.to_f - mean) ** 2 } / (sorted_arr.size - 1).to_f
      Math.sqrt(var)
    end
  end
end
