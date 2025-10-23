class DefenseVsPosition < ApplicationRecord
  belongs_to :team
  belongs_to :season

  serialize :data, JSON

  # Build full dataset (averages + ranks) for all teams in a season
  def self.rebuild_all_for_season(season)
    puts "Rebuilding DefenseVsPosition data for season: #{season.name}"
    all_averages = {}

    Team.find_each do |team|
      averages = team.average_stats_allowed_by_position(season)
      team.update_defense_vs_position!(season, averages)
      all_averages[team.id] = averages
    end

    positions = %w[PG SG SF PF C G F]
    stats = %i[points rebounds assists]

    positions.each do |position|
      stats.each do |stat|
        ranked = all_averages.sort_by { |_, avg| avg.dig(position, stat) || Float::INFINITY }

        ranked.each_with_index do |(team_id, _), index|
          team_record = find_by(team_id: team_id, season_id: season.id)
          next unless team_record&.data

          team_record.data[position] ||= {}
          team_record.data[position]["#{stat}_rank"] = index + 1
          team_record.save!
        end
      end
    end

    puts "DefenseVsPosition updated for #{Team.count} teams in #{season.name}."
  end
end
