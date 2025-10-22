class CreateHealths < ActiveRecord::Migration[7.1]
  def change
    create_table :healths do |t|
      t.references :player, null: false, foreign_key: true
      t.string :status
      t.text :description
      t.date :last_update

      t.timestamps
    end
  end
end
