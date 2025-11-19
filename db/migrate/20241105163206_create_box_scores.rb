class CreateBoxScores < ActiveRecord::Migration[7.1]
  def change
    create_table :box_scores do |t|
      t.references :game, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.string :minutes_played
      t.integer :field_goals
      t.integer :field_goals_attempted
      t.float :field_goal_percentage
      t.integer :three_point_field_goals
      t.integer :three_point_field_goals_attempted
      t.float :three_point_percentage
      t.integer :free_throws
      t.integer :free_throws_attempted
      t.float :free_throw_percentage
      t.integer :offensive_rebounds
      t.integer :defensive_rebounds
      t.integer :total_rebounds
      t.integer :assists
      t.integer :steals
      t.integer :blocks
      t.integer :turnovers
      t.integer :personal_fouls
      t.integer :points
      t.float :game_score
      t.float :plus_minus

      t.timestamps
    end
  end
end
