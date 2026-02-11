module Simulations
  class LeagueContext
    DEFAULT_PACE = 98.5
    DEFAULT_ORtg = 113.0
    DEFAULT_DRtg = 113.0

    attr_reader :pace_avg, :off_rtg_avg, :def_rtg_avg, :ppp_avg

    def initialize(season:)
      @season = season
      compute!
    end

    private

    def compute!
      rows = TeamAdvancedStat.where(season_id: @season.id).pluck(:stats)

      paces = []
      offs  = []
      defs  = []

      rows.each do |stats|
        next if stats.blank?

        pace = stats["pace"].to_f
        off  = stats["off_rtg"].to_f
        dr   = stats["def_rtg"].to_f

        paces << pace if pace > 0
        offs  << off  if off  > 0
        defs  << dr   if dr   > 0
      end

      @pace_avg    = avg_or_default(paces, DEFAULT_PACE)
      @off_rtg_avg = avg_or_default(offs,  DEFAULT_ORtg)
      @def_rtg_avg = avg_or_default(defs,  DEFAULT_DRtg)

      # Treat league average PPP as league average ORtg / 100
      @ppp_avg = @off_rtg_avg / 100.0
    end

    def avg_or_default(arr, fallback)
      return fallback.to_f if arr.blank?
      arr.sum.to_f / arr.size.to_f
    end
  end
end
