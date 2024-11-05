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
end
