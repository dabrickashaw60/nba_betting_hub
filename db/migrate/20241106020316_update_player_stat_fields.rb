class UpdatePlayerStatFields < ActiveRecord::Migration[7.0]
  def change
    # Rename fields to match BoxScore
    rename_column :player_stats, :field_goals_per_game, :field_goals
    rename_column :player_stats, :field_goals_attempted_per_game, :field_goals_attempted
    rename_column :player_stats, :three_pointers_per_game, :three_point_field_goals
    rename_column :player_stats, :three_pointers_attempted_per_game, :three_point_field_goals_attempted
    rename_column :player_stats, :three_point_percentage, :three_point_percentage
    rename_column :player_stats, :free_throws_per_game, :free_throws
    rename_column :player_stats, :free_throws_attempted_per_game, :free_throws_attempted
    rename_column :player_stats, :free_throw_percentage, :free_throw_percentage
    rename_column :player_stats, :offensive_rebounds_per_game, :offensive_rebounds
    rename_column :player_stats, :defensive_rebounds_per_game, :defensive_rebounds
    rename_column :player_stats, :total_rebounds_per_game, :total_rebounds
    rename_column :player_stats, :assists_per_game, :assists
    rename_column :player_stats, :steals_per_game, :steals
    rename_column :player_stats, :blocks_per_game, :blocks
    rename_column :player_stats, :turnovers_per_game, :turnovers
    rename_column :player_stats, :personal_fouls_per_game, :personal_fouls
    rename_column :player_stats, :points_per_game, :points

    # Rename minutes_per_game to minutes_played (or create it if it doesn’t exist)
    rename_column :player_stats, :minutes_per_game, :minutes_played

    # Add missing fields that exist in BoxScore but not in PlayerStat
    add_column :player_stats, :game_score, :float unless column_exists?(:player_stats, :game_score)
    add_column :player_stats, :plus_minus, :float unless column_exists?(:player_stats, :plus_minus)
  end
end
