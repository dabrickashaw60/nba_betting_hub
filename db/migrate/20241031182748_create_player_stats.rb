# db/migrate/xxxxxx_create_player_stats.rb
class CreatePlayerStats < ActiveRecord::Migration[7.1]
  def change
    create_table :player_stats do |t|
      t.references :player, foreign_key: true
      t.integer :season
      t.integer :games_played
      t.integer :games_started
      t.float :minutes_per_game
      t.float :field_goals_per_game
      t.float :field_goals_attempted_per_game
      t.float :field_goal_percentage
      t.float :three_pointers_per_game
      t.float :three_pointers_attempted_per_game
      t.float :three_point_percentage
      t.float :two_pointers_per_game
      t.float :two_pointers_attempted_per_game
      t.float :two_point_percentage
      t.float :free_throws_per_game
      t.float :free_throws_attempted_per_game
      t.float :free_throw_percentage
      t.float :offensive_rebounds_per_game
      t.float :defensive_rebounds_per_game
      t.float :total_rebounds_per_game
      t.float :assists_per_game
      t.float :steals_per_game
      t.float :blocks_per_game
      t.float :turnovers_per_game
      t.float :personal_fouls_per_game
      t.float :points_per_game

      t.timestamps
    end
  end
end
