class AddAdvancedStatsToPlayerStats < ActiveRecord::Migration[6.1]
  def change
    add_column :player_stats, :true_shooting_pct, :float
    add_column :player_stats, :effective_fg_pct, :float
    add_column :player_stats, :three_point_attempt_rate, :float
    add_column :player_stats, :free_throw_rate, :float
    add_column :player_stats, :offensive_rebound_pct, :float
    add_column :player_stats, :defensive_rebound_pct, :float
    add_column :player_stats, :total_rebound_pct, :float
    add_column :player_stats, :assist_pct, :float
    add_column :player_stats, :steal_pct, :float
    add_column :player_stats, :block_pct, :float
    add_column :player_stats, :turnover_pct, :float
    add_column :player_stats, :usage_pct, :float
    add_column :player_stats, :offensive_rating, :float
    add_column :player_stats, :defensive_rating, :float
    add_column :player_stats, :box_plus_minus, :float
  end
end
