class CreateProjectionDistributions < ActiveRecord::Migration[6.1]
  def change
    create_table :projection_distributions do |t|
      t.date :date
      t.references :season, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.references :opponent_team, null: false, foreign_key: { to_table: :teams }
      t.string :model_version
      t.integer :sims_count

      t.float :minutes_mean
      t.float :minutes_sd
      t.float :minutes_p10
      t.float :minutes_p50
      t.float :minutes_p90

      t.float :points_mean
      t.float :points_sd
      t.float :points_p10
      t.float :points_p50
      t.float :points_p90

      t.float :rebounds_mean
      t.float :rebounds_sd
      t.float :rebounds_p10
      t.float :rebounds_p50
      t.float :rebounds_p90

      t.float :assists_mean
      t.float :assists_sd
      t.float :assists_p10
      t.float :assists_p50
      t.float :assists_p90

      t.float :threes_mean
      t.float :threes_sd
      t.float :threes_p10
      t.float :threes_p50
      t.float :threes_p90

      t.timestamps
    end

    add_index :projection_distributions,
      [:date, :player_id, :model_version],
      unique: true,
      name: "idx_proj_dist_unique"
  end
end
