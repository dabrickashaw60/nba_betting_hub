module Simulations
  class GameFromPlayerMeans
    MODEL_VERSION = "game_from_player_mc_means_v1".freeze

    def initialize(date:, season: nil, player_model_version: "proj_mc_v1")
      @date = date
      @season = season || Season.find_by(current: true)
      raise "No season" unless @season
      @player_model_version = player_model_version
    end

    def build!(game_id:, persist: true)
      game = Game.includes(:home_team, :visitor_team).find(game_id)

      home_rows = rows_for(team_id: game.home_team_id, opp_id: game.visitor_team_id)
      vis_rows  = rows_for(team_id: game.visitor_team_id, opp_id: game.home_team_id)

      home_mean = home_rows.sum(&:points_mean).to_f
      vis_mean  = vis_rows.sum(&:points_mean).to_f

      payload = {
        date: @date,
        season_id: @season.id,
        game_id: game.id,
        model_version: MODEL_VERSION,

        home_team_id: game.home_team_id,
        visitor_team_id: game.visitor_team_id,

        home_points_mean: home_mean,
        visitor_points_mean: vis_mean,
        spread_mean: (home_mean - vis_mean),
        total_mean: (home_mean + vis_mean),

        source_player_model_version: @player_model_version
      }

      save!(payload) if persist
      payload
    end

    private

    def rows_for(team_id:, opp_id:)
      rows = ProjectionDistribution.where(
        date: @date,
        team_id: team_id,
        opponent_team_id: opp_id,
        model_version: @player_model_version
      )
      raise "No ProjectionDistribution rows for team #{team_id} vs #{opp_id} on #{@date}" if rows.blank?
      rows
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
        sims_count: 0, # important: not a sim

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
            visitor_points_mean: payload[:visitor_points_mean],
            spread_mean: payload[:spread_mean],
            total_mean: payload[:total_mean]
          }
        }
      )

      gs.save!
      gs
    end
  end
end
