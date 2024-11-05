class AddPointsToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :visitor_points, :integer
    add_column :games, :home_points, :integer
  end
end
