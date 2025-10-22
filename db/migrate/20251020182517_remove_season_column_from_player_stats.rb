class RemoveSeasonColumnFromPlayerStats < ActiveRecord::Migration[6.1]
  def change
    remove_column :player_stats, :season, :integer
  end
end
