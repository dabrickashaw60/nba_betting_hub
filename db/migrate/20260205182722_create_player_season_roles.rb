class CreatePlayerSeasonRoles < ActiveRecord::Migration[6.1]
  def change
    create_table :player_season_roles do |t|
      t.references :season, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true

      # snapshot fields (useful for viewing; will be updated when we rebuild)
      t.integer :team_id
      t.string :position

      t.integer :games_played,  null: false, default: 0
      t.integer :games_started, null: false, default: 0
      t.integer :bench_games,   null: false, default: 0

      t.decimal :start_rate, precision: 6, scale: 4, null: false, default: 0.0

      t.timestamps
    end

    add_index :player_season_roles, [:season_id, :player_id], unique: true
    add_index :player_season_roles, [:season_id, :team_id]
  end
end
