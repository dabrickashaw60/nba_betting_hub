class CreateGameOdds < ActiveRecord::Migration[6.1]
  def change
    create_table :game_odds do |t|
      t.references :game, null: false, foreign_key: true
      t.string :provider
      t.datetime :start_time_utc
      t.datetime :pulled_at
      t.decimal :home_spread, precision: 6, scale: 2
      t.decimal :away_spread, precision: 6, scale: 2
      t.decimal :total, precision: 6, scale: 2
      t.integer :home_ml
      t.integer :away_ml
      t.timestamps
    end

    add_index :game_odds, [:game_id, :provider], unique: true 
  end
end
