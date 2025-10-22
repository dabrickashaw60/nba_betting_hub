class RemoveGamesStartedFromPlayerStats < ActiveRecord::Migration[7.1]
  def change
    remove_column :player_stats, :games_started, :integer

  end
end
