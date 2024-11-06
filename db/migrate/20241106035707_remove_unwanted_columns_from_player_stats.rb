class RemoveUnwantedColumnsFromPlayerStats < ActiveRecord::Migration[7.1]
  def change
    remove_column :player_stats, :two_pointers_per_game, :float
    remove_column :player_stats, :two_pointers_attempted_per_game, :float
    remove_column :player_stats, :two_point_percentage, :float
  end
end
