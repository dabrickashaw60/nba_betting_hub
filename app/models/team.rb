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
  
    games = Game.where("visitor_team_id = ? OR home_team_id = ?", id, id)
  
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
  
    averages
  end
  
  def self.update_defense_averages
    all_averages = {}
  
    # Step 1: Calculate averages for each team
    Team.find_each do |team|
      all_averages[team.id] = team.average_stats_allowed_by_position
      team.update(defense_vs_position: all_averages[team.id])
    end
  
    # Step 2: Calculate ranks for each stat by position
    positions = ["PG", "SG", "SF", "PF", "C", "G", "F"]
    stats = [:points, :rebounds, :assists]
  
    positions.each do |position|
      stats.each do |stat|
        # Sort teams by each stat for the current position
        ranked_teams = all_averages.sort_by { |_, averages| averages.dig(position, stat) || Float::INFINITY }
  
        # Step 3: Update each team with the rank for the current stat and position
        ranked_teams.each_with_index do |(team_id, averages), index|
          team = Team.find(team_id)
          team.defense_vs_position[position][:"#{stat}_rank"] = index + 1
          team.save
        end
      end
    end
  end
  
  
end
