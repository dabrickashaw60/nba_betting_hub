class Team < ApplicationRecord
  has_many :standings, class_name: 'Standing'
  has_many :players, dependent: :nullify

  has_many :home_games, class_name: 'Game', foreign_key: 'home_team_id'
  has_many :away_games, class_name: 'Game', foreign_key: 'visitor_team_id'

  has_many :defense_vs_positions, dependent: :destroy

  validates :name, :abbreviation, presence: true

  # -------------------------------------------------------------------
  # 🏀 Combined association: all games (home + away)
  # -------------------------------------------------------------------
  def games
    Game.where("home_team_id = ? OR visitor_team_id = ?", id, id)
  end

  # -------------------------------------------------------------------
  # 🧮 Calculate average stats allowed by position for this team
  # -------------------------------------------------------------------
  def average_stats_allowed_by_position(season)
    valid_positions = %w[PG SG SF PF C]

    stats_by_position = Hash.new do |hash, key|
      hash[key] = { points: { total: 0, games: 0 },
                    rebounds: { total: 0, games: 0 },
                    assists: { total: 0, games: 0 } }
    end

    games = Game.where("(visitor_team_id = ? OR home_team_id = ?) AND season_id = ? AND date < ?",
                      id, id, season.id, Date.today)
                .order(date: :desc)
                .limit(10)

    games.each do |game|
      opponent_team_id = (game.visitor_team_id == id ? game.home_team_id : game.visitor_team_id)
      opponent_box_scores = BoxScore.joins(:player)
                                    .where(game_id: game.id, team_id: opponent_team_id)

      positions_counted = Hash.new { |h, k| h[k] = { points: false, rebounds: false, assists: false } }

      opponent_box_scores.each do |box_score|
        position = box_score.player.position
        next unless valid_positions.include?(position)

        stats_by_position[position][:points][:total]   += box_score.points
        stats_by_position[position][:rebounds][:total] += box_score.total_rebounds
        stats_by_position[position][:assists][:total]  += box_score.assists

        %i[points rebounds assists].each do |stat|
          unless positions_counted[position][stat]
            stats_by_position[position][stat][:games] += 1
            positions_counted[position][stat] = true
          end
        end
      end
    end

    # Compute averages
    averages = {}
    stats_by_position.each do |position, stat_group|
      averages[position] = {
        points:   stat_group[:points][:games] > 0 ? (stat_group[:points][:total].to_f / stat_group[:points][:games]).round(2) : 0,
        rebounds: stat_group[:rebounds][:games] > 0 ? (stat_group[:rebounds][:total].to_f / stat_group[:rebounds][:games]).round(2) : 0,
        assists:  stat_group[:assists][:games] > 0 ? (stat_group[:assists][:total].to_f / stat_group[:assists][:games]).round(2) : 0,
        games:    [stat_group[:points][:games], stat_group[:rebounds][:games], stat_group[:assists][:games]].max
      }
    end

    # Combine G and F groups (weighted + tolerant)
    pg = averages["PG"]
    sg = averages["SG"]
    sf = averages["SF"]
    pf = averages["PF"]

    if pg || sg
      averages["G"] = combine_positions(pg || sg, sg || pg)
    end
    if sf || pf
      averages["F"] = combine_positions(sf || pf, pf || sf)
    end

    averages
  end

  def combine_positions(pos1, pos2)
    total_games_1 = pos1[:games] || 1
    total_games_2 = pos2[:games] || 1
    total_games = total_games_1 + total_games_2

    {
      points: ((pos1[:points] * total_games_1 + pos2[:points] * total_games_2) / total_games).round(2),
      rebounds: ((pos1[:rebounds] * total_games_1 + pos2[:rebounds] * total_games_2) / total_games).round(2),
      assists: ((pos1[:assists] * total_games_1 + pos2[:assists] * total_games_2) / total_games).round(2),
      games: total_games
    }
  end



  # -------------------------------------------------------------------
  # 🧩 Interface to DefenseVsPosition model
  # -------------------------------------------------------------------

  # Return parsed defense data (Hash) for a given season
  def defense_data_for(season)
    record = DefenseVsPosition.find_by(team_id: id, season_id: season.id)
    record&.data || {}
  end

  # Save/update defense data for a given season
  def update_defense_vs_position!(season, data)
    record = defense_vs_positions.find_or_initialize_by(season: season)
    record.update!(data: data)
  end

  # Fully rebuild and persist the latest defense data for this season
  def rebuild_defense_vs_position!(season)
    data = average_stats_allowed_by_position(season)
    update_defense_vs_position!(season, data)
  end

  # -------------------------------------------------------------------
  # 📊 Fetch opponent defense data for a specific game
  # -------------------------------------------------------------------
  def opponent_defense_for_game(game)
    opponent_team_id = (game.visitor_team_id == id ? game.home_team_id : game.visitor_team_id)
    DefenseVsPosition.find_by(team_id: opponent_team_id, season_id: game.season_id)&.data || {}
  end
end
