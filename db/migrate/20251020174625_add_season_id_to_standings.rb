class AddSeasonIdToStandings < ActiveRecord::Migration[6.1]
  def change
    add_column :standings, :season_id, :integer
  end
end
