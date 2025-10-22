class AddSeasonIdToGames < ActiveRecord::Migration[6.1]
  def change
    add_column :games, :season_id, :integer
  end
end
