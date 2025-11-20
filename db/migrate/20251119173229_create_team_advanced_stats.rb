class CreateTeamAdvancedStats < ActiveRecord::Migration[6.1]
  def change
    create_table :team_advanced_stats do |t|
      t.references :team, null: false, foreign_key: true
      t.references :season, null: false, foreign_key: true
      t.json :stats

      t.timestamps
    end
  end
end
