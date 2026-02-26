class GameOdd < ApplicationRecord
  belongs_to :game
  validates :provider, presence: true
end
