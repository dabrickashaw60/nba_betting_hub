class AddAdvancedStatsToBoxScores < ActiveRecord::Migration[6.1]
  def change
    add_column :box_scores, :true_shooting_pct, :float
    add_column :box_scores, :effective_fg_pct, :float
    add_column :box_scores, :three_point_attempt_rate, :float
    add_column :box_scores, :free_throw_rate, :float
    add_column :box_scores, :offensive_rebound_pct, :float
    add_column :box_scores, :defensive_rebound_pct, :float
    add_column :box_scores, :total_rebound_pct, :float
    add_column :box_scores, :assist_pct, :float
    add_column :box_scores, :steal_pct, :float
    add_column :box_scores, :block_pct, :float
    add_column :box_scores, :turnover_pct, :float
    add_column :box_scores, :usage_pct, :float
    add_column :box_scores, :offensive_rating, :integer
    add_column :box_scores, :defensive_rating, :integer
    add_column :box_scores, :box_plus_minus, :float
  end
end
