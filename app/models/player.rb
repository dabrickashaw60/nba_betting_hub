class Player < ApplicationRecord
  belongs_to :team, optional: true
  has_many :player_stats, dependent: :destroy
  has_many :box_scores


  has_one :player_stat, -> { where(season: 2025) } # Assuming 2025 is the season you're interested in
  
  validates :name, presence: true
  validates :from_year, :to_year, :position, :height, :weight, :birth_date, presence: true


  def update_average_stats
    total_games = box_scores.count
    return if total_games.zero?

    self.points_per_game = box_scores.sum(:points) / total_games.to_f
    self.rebounds_per_game = box_scores.sum(:total_rebounds) / total_games.to_f
    self.assists_per_game = box_scores.sum(:assists) / total_games.to_f
    # Continue for other stats if needed
    self.save
  end

  
end
