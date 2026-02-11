# app/models/game_simulation.rb
class GameSimulation < ApplicationRecord
  belongs_to :game
  belongs_to :season
  belongs_to :home_team, class_name: "Team"
  belongs_to :visitor_team, class_name: "Team"

  attribute :meta, :json, default: {}

  validates :date, :game_id, :season_id, :home_team_id, :visitor_team_id, :model_version, presence: true

  before_validation :normalize_meta

  private

  def normalize_meta
    case meta
    when nil
      self.meta = {}
    when Hash
      # good
    when String
      begin
        self.meta = JSON.parse(meta) # turn JSON text into a hash
      rescue
        self.meta = {}               # if it was YAML/garbage, force empty hash
      end
    else
      self.meta = {}
    end
  end
end
