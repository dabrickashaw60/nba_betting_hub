# app/models/projection.rb
class Projection < ApplicationRecord
  belongs_to :projection_run
  belongs_to :player
  belongs_to :team
  belongs_to :opponent_team, class_name: "Team"

  validates :date, :player_id, :team_id, :opponent_team_id, presence: true
  attribute :explain, :json
end
