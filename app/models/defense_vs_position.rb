class DefenseVsPosition < ApplicationRecord
  belongs_to :team
  belongs_to :season

  serialize :data, JSON

  # Build full dataset (averages + ranks) for all teams in a season
  def self.rebuild_all_for_season(season)
    puts "Rebuilding DefenseVsPosition data for season: #{season.name}"
    all_averages = {}

    # STEP 1: Collect all teams’ averages first
    Team.find_each do |team|
      averages = team.average_stats_allowed_by_position(season)
      team.update_defense_vs_position!(season, averages)
      all_averages[team.id] = averages
    end

    positions = %w[PG SG SF PF C G F]
    stats = %i[points rebounds assists]

    # STEP 2: Rank teams by stat and position
    positions.each do |position|
      stats.each do |stat|
        # Sort by lowest stat first — teams that allow fewer points = better rank
        ranked_teams = all_averages
          .select { |_, avg| avg[position].present? && avg[position][stat].present? }
          .sort_by { |_, avg| avg[position][stat] }

        ranked_teams.each_with_index do |(team_id, _), index|
          record = DefenseVsPosition.find_by(team_id: team_id, season_id: season.id)
          next unless record

          # Ensure position exists in record data
          record.data[position] ||= {}

          # Assign rank: 1 = best (least allowed)
          record.data[position]["#{stat}_rank"] = index + 1
          record.save!
        end
      end
    end

    puts "✅ DefenseVsPosition ranks rebuilt successfully for #{Team.count} teams in #{season.name}."
  end
end
