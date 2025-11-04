# db/migrate/20251102_create_projections.rb
class CreateProjections < ActiveRecord::Migration[6.1]
  def change
    create_table :projections do |t|
      t.references :projection_run, null: false, foreign_key: true
      t.references :player,         null: false, foreign_key: true
      t.references :team,           null: false, foreign_key: true
      t.references :opponent_team,  null: false, foreign_key: { to_table: :teams }

      t.date    :date, null: false

      # Inputs (diagnostic)
      t.float   :expected_minutes
      t.float   :usage_pct
      t.string  :position
      t.string  :injury_status
      t.float   :dvp_pts_mult
      t.float   :dvp_reb_mult
      t.float   :dvp_ast_mult

      # Outputs (core counting stats)
      t.float   :proj_points
      t.float   :proj_rebounds
      t.float   :proj_assists
      t.float   :proj_threes
      t.float   :proj_steals
      t.float   :proj_blocks
      t.float   :proj_turnovers
      t.float   :proj_plus_minus

      # Combos for convenience
      t.float   :proj_pa
      t.float   :proj_pr
      t.float   :proj_ra
      t.float   :proj_pra

      # Confidence (optional, can fill later)
      t.float   :stdev_points
      t.float   :stdev_rebounds
      t.float   :stdev_assists

      t.timestamps
    end

    add_index :projections, [:date, :player_id], unique: true
    add_index :projections, [:date, :team_id]
    add_index :projections, [:date, :opponent_team_id]
  end
end
