class PlayerStat < ApplicationRecord
  belongs_to :player
  validates :season, presence: true
end
