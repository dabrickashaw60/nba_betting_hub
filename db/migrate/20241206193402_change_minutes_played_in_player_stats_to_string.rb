class ChangeMinutesPlayedInPlayerStatsToString < ActiveRecord::Migration[6.1]
  def change
    change_column :player_stats, :minutes_played, :string

  end
end
