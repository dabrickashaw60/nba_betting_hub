# db/migrate/20260209000000_create_game_simulations.rb
class CreateGameSimulations < ActiveRecord::Migration[6.1]
  def change
    create_table :game_simulations do |t|
      t.date :date, null: false
      t.bigint :game_id, null: false
      t.bigint :season_id, null: false

      t.bigint :home_team_id, null: false
      t.bigint :visitor_team_id, null: false

      t.string :model_version, null: false
      t.integer :sims_count, null: false, default: 1

      # Team totals (simulated)
      t.integer :home_points, default: 0, null: false
      t.integer :visitor_points, default: 0, null: false
      t.decimal :home_rebounds, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_rebounds, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :home_assists, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_assists, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :home_threes, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_threes, precision: 8, scale: 2, default: 0.0, null: false

      # Baseline totals (sum of projections before any noise/scaling)
      t.decimal :home_baseline_points, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_baseline_points, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :home_baseline_rebounds, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_baseline_rebounds, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :home_baseline_assists, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_baseline_assists, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :home_baseline_threes, precision: 8, scale: 2, default: 0.0, null: false
      t.decimal :visitor_baseline_threes, precision: 8, scale: 2, default: 0.0, null: false

      # Multipliers applied to reconcile to simulated totals
      t.decimal :home_scale, precision: 8, scale: 4, default: 1.0, null: false
      t.decimal :visitor_scale, precision: 8, scale: 4, default: 1.0, null: false

      t.json :meta
      t.timestamps
    end

    add_index :game_simulations, [:date, :game_id, :model_version], unique: true
    add_index :game_simulations, :game_id
    add_index :game_simulations, :date
  end
end
