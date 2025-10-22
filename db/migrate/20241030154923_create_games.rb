class CreateGames < ActiveRecord::Migration[7.1]
  def change
    create_table :games do |t|
      t.date :date
      t.time :time
      t.references :home_team, null: false, foreign_key: { to_table: :teams }
      t.references :away_team, null: false, foreign_key: { to_table: :teams }
      t.string :location
      t.integer :home_score
      t.integer :away_score
      t.integer :season
      t.integer :week

      t.timestamps
    end
  end
end
