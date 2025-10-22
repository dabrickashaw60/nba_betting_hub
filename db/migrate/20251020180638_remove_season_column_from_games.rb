class RemoveSeasonColumnFromGames < ActiveRecord::Migration[6.1]
  def change
    remove_column :games, :season, :integer
  end
end
