class RemoveUnnecessaryColumnsFromGames < ActiveRecord::Migration[7.0]
  def change
    remove_column :games, :home_score, :integer
    remove_column :games, :away_score, :integer
    remove_column :games, :visitor_pts, :integer
    remove_column :games, :home_pts, :integer
    remove_column :games, :arena, :string
  end
end
