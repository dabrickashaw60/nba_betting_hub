class TeamAdvancedStatsRanker
  STAT_KEYS = %w[
    age wins losses wins_pyth losses_pyth mov sos srs
    off_rtg def_rtg net_rtg pace
    fta_per_fga_pct fg3a_per_fga_pct ts_pct efg_pct tov_pct orb_pct ft_rate
    opp_efg_pct opp_tov_pct drb_pct opp_ft_rate
  ]

  REVERSE_STATS = %w[
    def_rtg
    opp_efg_pct
    opp_tov_pct
    drb_pct
    opp_ft_rate
    tov_pct
  ]

  def initialize(season)
    @season = season
    @records = TeamAdvancedStat.where(season: season)
  end

  def generate_rankings
    return if @records.empty?

    STAT_KEYS.each do |key|
      values = @records.map { |r| { id: r.id, value: numeric(r.stats[key]) } }

      ranked_values = if REVERSE_STATS.include?(key)
        values.sort_by { |h| h[:value] } # lower better
      else
        values.sort_by { |h| -h[:value] } # higher better
      end

      ranked_values.each_with_index do |data, index|
        record = @records.find { |r| r.id == data[:id] }

        rankings_hash = safe_hash(record.rankings)
        rankings_hash["#{key}_rank"] = index + 1

        record.rankings = rankings_hash
        record.save!
      end
    end
  end

  private

  def safe_hash(val)
    return {} if val.nil?
    return val if val.is_a?(Hash)

    begin
      parsed = JSON.parse(val)
      return parsed if parsed.is_a?(Hash)
    rescue
      return {}
    end

    {}
  end

  def numeric(val)
    return 0 if val.nil?

    s = val.to_s.delete(",")

    s = s.gsub("+", "")
    s = "0#{s}" if s.start_with?(".")
    s = s.sub(/-\./, "-0.")

    s.to_f
  end
end
