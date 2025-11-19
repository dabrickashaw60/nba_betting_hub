class BoxScore < ApplicationRecord
  belongs_to :game
  belongs_to :team
  belongs_to :player

  after_save :update_player_season_stats

  private

  def update_player_season_stats
    PlayerStat.update_season_averages(player)
  end
  
end
