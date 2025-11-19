class AddArenaToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :arena, :string
  end
end
