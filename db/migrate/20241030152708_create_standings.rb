class CreateStandings < ActiveRecord::Migration[7.1]
  def change
    create_table :standings do |t|
      t.references :team, foreign_key: true
      t.integer :season
      t.integer :wins
      t.integer :losses
      t.float :win_percentage
      t.string :games_behind
      t.float :points_per_game
      t.float :opponent_points_per_game
      t.float :srs
      t.timestamps
    end
  end
end
