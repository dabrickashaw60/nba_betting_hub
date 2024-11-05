class AddGameDurationToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :game_duration, :string
  end
end
