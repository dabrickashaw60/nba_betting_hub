# db/migrate/xxxxxx_create_players.rb
class CreatePlayers < ActiveRecord::Migration[7.1]
  def change
    create_table :players do |t|
      t.string :name, null: false
      t.integer :from_year, null: false
      t.integer :to_year, null: false
      t.string :position, null: false
      t.string :height, null: false
      t.integer :weight, null: false
      t.date :birth_date, null: false
      t.string :college, null: false

      t.timestamps
    end
  end
end
