class RemoveAwayTeamIdFromGames < ActiveRecord::Migration[7.1]
  def change
    remove_column :games, :away_team_id
  end
end
