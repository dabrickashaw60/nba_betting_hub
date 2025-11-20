class AddRankingsToTeamAdvancedStats < ActiveRecord::Migration[6.1]
  def change
    add_column :team_advanced_stats, :rankings, :json
  end
end
