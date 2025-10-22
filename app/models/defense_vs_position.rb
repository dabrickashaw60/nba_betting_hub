# app/models/defense_vs_position.rb
class DefenseVsPosition < ApplicationRecord
  belongs_to :team
  belongs_to :season

  validates :team_id, :season_id, presence: true
  validates :data, presence: true

  serialize :data, JSON
end
