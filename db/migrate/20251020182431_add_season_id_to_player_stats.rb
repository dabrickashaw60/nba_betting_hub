class AddSeasonIdToPlayerStats < ActiveRecord::Migration[6.1]
  def change
    add_column :player_stats, :season_id, :integer
  end
end
