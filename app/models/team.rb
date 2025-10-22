class Team < ApplicationRecord
  has_many :standings, class_name: 'Standing'  # Make sure this references the correct singular model
  has_many :players, dependent: :nullify

  has_many :home_games, class_name: 'Game', foreign_key: 'home_team_id'
  has_many :away_games, class_name: 'Game', foreign_key: 'visitor_team_id'

  validates :name, presence: true
  validates :abbreviation, presence: true

  # Combined association to fetch all games (home and away)
  def games
    Game.where("home_team_id = ? OR visitor_team_id = ?", id, id)
  end

  def average_stats_allowed_by_position
    valid_positions = ["PG", "SG", "SF", "PF", "C"]

    stats_by_position = Hash.new { |hash, key| hash[key] = { points: { total: 0, games: 0 }, rebounds: { total: 0, games: 0 }, assists: { total: 0, games: 0 } } }

    #games = Game.where("visitor_team_id = ? OR home_team_id = ?", id, id)

    games = Game.where("(visitor_team_id = ? OR home_team_id = ?) AND date < ?", id, id, Date.today)
    .order(date: :desc)
    .limit(10)    

    games.each do |game|
      opponent_team_id = game.visitor_team_id == id ? game.home_team_id : game.visitor_team_id
      opponent_box_scores = BoxScore.joins(:player).where(game_id: game.id, team_id: opponent_team_id)
      positions_counted = Hash.new { |hash, key| hash[key] = { points: false, rebounds: false, assists: false } }

      opponent_box_scores.each do |box_score|
        position = box_score.player.position
        next unless valid_positions.include?(position)

        stats_by_position[position][:points][:total] += box_score.points
        stats_by_position[position][:rebounds][:total] += box_score.total_rebounds
        stats_by_position[position][:assists][:total] += box_score.assists

        unless positions_counted[position][:points]
          stats_by_position[position][:points][:games] += 1
          positions_counted[position][:points] = true
        end
        unless positions_counted[position][:rebounds]
          stats_by_position[position][:rebounds][:games] += 1
          positions_counted[position][:rebounds] = true
        end
        unless positions_counted[position][:assists]
          stats_by_position[position][:assists][:games] += 1
          positions_counted[position][:assists] = true
        end
      end
    end

    averages = Hash.new { |hash, key| hash[key] = {} }
    stats_by_position.each do |position, stats|
      stats.each do |stat, data|
        if data[:games] > 0
          averages[position][stat] = (data[:total].to_f / data[:games]).round(2)
        else
          averages[position][stat] = 0
        end
      end
    end

    if averages["PG"] && averages["SG"]
      averages["G"] = {
        points: ((averages["PG"][:points] + averages["SG"][:points]) / 2).round(2),
        rebounds: ((averages["PG"][:rebounds] + averages["SG"][:rebounds]) / 2).round(2),
        assists: ((averages["PG"][:assists] + averages["SG"][:assists]) / 2).round(2)
      }
    end

    if averages["SF"] && averages["PF"]
      averages["F"] = {
        points: ((averages["SF"][:points] + averages["PF"][:points]) / 2).round(2),
        rebounds: ((averages["SF"][:rebounds] + averages["PF"][:rebounds]) / 2).round(2),
        assists: ((averages["SF"][:assists] + averages["PF"][:assists]) / 2).round(2)
      }
    end

    Rails.logger.debug("Averages for team #{name}: #{averages.inspect}")

    averages
  end

  def self.update_team_defense_data
    Team.find_each do |team|
      begin
        # Ensure defense data is properly serialized into JSON format
        defense_data = team.defense_vs_position
        parsed_data = JSON.parse(defense_data || "{}") # Parse current data
        serialized_data = parsed_data.deep_stringify_keys.to_json # Convert to valid JSON

        team.update!(defense_vs_position: serialized_data)
        Rails.logger.info "Updated defense_vs_position for #{team.name}"
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse defense_vs_position for #{team.name}: #{e.message}"
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.error "Database error for #{team.name}: #{e.message}"
      end
    end
  end
  
def self.update_defense_averages
  all_averages = {}

  # Step 1: Calculate averages for each team
  Team.find_each do |team|
    averages = team.average_stats_allowed_by_position
    all_averages[team.id] = averages

    # Initialize defense_vs_position if missing or outdated
    defense_data = team.defense_vs_position.is_a?(String) ? JSON.parse(team.defense_vs_position) : {}
    defense_data.merge!(averages) # Merge new averages with existing data
    team.update!(defense_vs_position: defense_data.to_json) # Save back to database
  end

  # Step 2: Calculate ranks for each stat by position
  positions = ["PG", "SG", "SF", "PF", "C", "G", "F"]
  stats = [:points, :rebounds, :assists]

  positions.each do |position|
    stats.each do |stat|
      # Sort teams by the specific stat in ascending order (handling nil values as Infinity)
      ranked_teams = all_averages.sort_by do |_, averages|
        averages.dig(position, stat) || Float::INFINITY
      end

      # Assign ranks to the teams based on the sorted order
      ranked_teams.each_with_index do |(team_id, averages), index|
        team = Team.find(team_id)

        # Parse and ensure defense_vs_position is a hash
        defense_data = team.defense_vs_position.is_a?(String) ? JSON.parse(team.defense_vs_position) : {}
        defense_data[position] ||= {} # Ensure the position key exists

        # Update rank for the specific stat
        defense_data[position][:"#{stat}_rank"] = index + 1

        # Save updated defense_vs_position with both values and ranks
        team.update!(defense_vs_position: defense_data.to_json)
      end
    end
  end
end

def opponent_defense_for_game(game)
  # Determine the opponent
  opponent_team_id = game.visitor_team_id == id ? game.home_team_id : game.visitor_team_id
  opponent_team = Team.find(opponent_team_id)

  # Parse the opponent defense stats
  JSON.parse(opponent_team.defense_vs_position || "{}") rescue {}
end



end
