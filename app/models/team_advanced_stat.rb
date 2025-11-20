class TeamAdvancedStat < ApplicationRecord
  belongs_to :team
  belongs_to :season
  serialize :stats, JSON
  serialize :rankings, JSON  
end
