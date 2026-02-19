class ProjectionDistribution < ApplicationRecord
  belongs_to :season
  belongs_to :player
  belongs_to :team
  belongs_to :opponent_team, class_name: "Team"
end
