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

      # 1) Deterministic baseline projections
      puts "[PIPELINE] 1) BaselineModel..."
      Projections::BaselineModel.new(date: @date).run!

      # 2) Player MC distributions persisted
      puts "[PIPELINE] 2) DistributionSimulator..."
      Projections::DistributionSimulator.new(date: @date, season: @season, sims: @sims, force: @force).run!

      # 3) Game distributions from saved player MC
      puts "[PIPELINE] 3) GameFromPlayerDistributions..."
      game_ids = Game.where(date: @date, season_id: @season.id).pluck(:id)

      svc = Simulations::GameFromPlayerDistributions.new(date: @date, season: @season)

      game_ids.each do |gid|
        svc.build!(game_id: gid, sims: @sims, persist: true)
      rescue => e
        Rails.logger.warn "[PIPELINE] game_id=#{gid} failed: #{e.message}"
      end

      puts "[PIPELINE] done. games=#{game_ids.size}"
      true
    end
  end
end
