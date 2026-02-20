module Projections
  class DailyPipeline
    def initialize(date:, season: nil, sims: 500, force: false)
      @date  = date
      @season = season || Season.find_by(current: true)
      raise "No season" unless @season

      @sims  = sims.to_i
      @force = force
    end

    def run!
      puts "[PIPELINE] date=#{@date} season_id=#{@season.id} sims=#{@sims} force=#{@force}"

      # 1) Baseline projections (deterministic)
      puts "[PIPELINE] 1) BaselineModel..."
      Projections::BaselineModel.new(date: @date).run!

      # 2) Player MC distributions persisted (ProjectionDistribution, model_version: proj_mc_v1)
      puts "[PIPELINE] 2) DistributionSimulator..."
      Projections::DistributionSimulator.new(
        date: @date,
        season: @season,
        sims: @sims,
        force: @force
      ).run!

      # 3) Game lines from PLAYER MC MEANS (NO game Monte Carlo)
      puts "[PIPELINE] 3) GameFromPlayerMeans..."
      game_ids = Game.where(date: @date, season_id: @season.id).pluck(:id)

      builder = Simulations::GameFromPlayerMeans.new(
        date: @date,
        season: @season,
        player_model_version: Projections::DistributionSimulator::MODEL_VERSION # "proj_mc_v1"
      )

      game_ids.each do |gid|
        builder.build!(game_id: gid, persist: true)
      rescue => e
        Rails.logger.warn "[PIPELINE] game_id=#{gid} failed: #{e.message}"
      end

      puts "[PIPELINE] done. games=#{game_ids.size}"
      true
    end
  end
end
