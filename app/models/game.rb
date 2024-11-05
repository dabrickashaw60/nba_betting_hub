class Game < ApplicationRecord
  # Associations
  belongs_to :visitor_team, class_name: 'Team', foreign_key: 'visitor_team_id'
  belongs_to :home_team, class_name: 'Team', foreign_key: 'home_team_id'

  has_many :box_scores

  # Validations
  validates :visitor_team, presence: true
  validates :home_team, presence: true
  validates :date, :time, :location, :season, presence: true

  # Scopes to retrieve games by team roles
  scope :home_games, ->(team) { where(home_team: team) }
  scope :away_games, ->(team) { where(visitor_team: team) }
  scope :for_team, ->(team) { where('home_team_id = ? OR visitor_team_id = ?', team.id, team.id) }

  # Method to get the standings record for the home team
  def home_team_record
    Standing.find_by(team: home_team, season: season)&.record
  end

  # Method to get the standings record for the visitor team
  def visitor_team_record
    Standing.find_by(team: visitor_team, season: season)&.record
  end

  def opponent_for(team)
    team == home_team ? visitor_team : home_team
  end

  # Helper method to check if the game has been played
  def played?
    visitor_points.present? && home_points.present?
  end

  # Format date for display
  def formatted_date
    date.strftime("%B %d, %Y")
  end

  # Format time for display
  def formatted_time
    time&.strftime("%I:%M %p")
  end
end
