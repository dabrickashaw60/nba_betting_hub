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
  
  def average_points_allowed_by_position
    # Only consider these specific positions
    valid_positions = ["PG", "SG", "SF", "PF", "C"]
    stats_by_position = Hash.new { |hash, key| hash[key] = { total_points: 0, games: 0 } }

    # Get all games involving this team
    games = Game.where("visitor_team_id = ? OR home_team_id = ?", id, id)

    games.each do |game|
      # Determine the opposing team
      opponent_team_id = game.visitor_team_id == id ? game.home_team_id : game.visitor_team_id

      # Fetch box scores for players on the opposing team for this game
      opponent_box_scores = BoxScore.joins(:player)
                                    .where(game_id: game.id, team_id: opponent_team_id)

      # Track if a position has been counted for this game to avoid duplicate increments
      positions_counted = Hash.new(false)

      # Iterate through each player's box score
      opponent_box_scores.each do |box_score|
        position = box_score.player.position

        # Only include the specified positions
        next unless valid_positions.include?(position)

        # Accumulate points for each position
        stats_by_position[position][:total_points] += box_score.points

        # Increment the game count for each position only once per game
        unless positions_counted[position]
          stats_by_position[position][:games] += 1
          positions_counted[position] = true
        end
      end
    end

    # Calculate the average points allowed per game for each position
    averages = {}
    stats_by_position.each do |position, data|
      if data[:games] > 0
        averages[position] = (data[:total_points].to_f / data[:games]).round(2)
      else
        averages[position] = 0
      end
    end

    # Calculate G (Guard) and F (Forward) averages
    if averages["PG"] && averages["SG"]
      averages["G"] = ((averages["PG"] + averages["SG"]) / 2).round(2)
    end

    if averages["SF"] && averages["PF"]
      averages["F"] = ((averages["SF"] + averages["PF"]) / 2).round(2)
    end

    # Log the results for debugging purposes
    puts "Intermediate stats_by_position data: #{stats_by_position}"
    puts "Final averages: #{averages}"

    averages
  end
end
