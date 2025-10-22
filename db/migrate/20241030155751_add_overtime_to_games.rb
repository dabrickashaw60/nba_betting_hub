class AddOvertimeToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :overtime, :boolean
  end
end
