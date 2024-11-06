class Player < ApplicationRecord
  belongs_to :team, optional: true
  has_many :player_stats, dependent: :destroy
  has_many :box_scores


  has_one :player_stat, -> { where(season: PlayerStat::SEASON) }
  
  validates :name, presence: true
  validates :from_year, :to_year, :position, :height, :weight, :birth_date, presence: true
  
end
