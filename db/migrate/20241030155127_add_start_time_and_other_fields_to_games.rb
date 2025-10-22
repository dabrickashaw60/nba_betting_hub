class AddStartTimeAndOtherFieldsToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :start_time, :time
    add_column :games, :visitor_pts, :integer
    add_column :games, :home_pts, :integer
    add_column :games, :attendance, :integer
    add_column :games, :duration, :string
    add_column :games, :notes, :string
  end
end
