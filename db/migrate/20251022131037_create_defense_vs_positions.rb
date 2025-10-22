class CreateDefenseVsPositions < ActiveRecord::Migration[6.1]
  def change
    create_table :defense_vs_positions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :season, null: false, foreign_key: true
      t.json :data

      t.timestamps
    end
  end
end
