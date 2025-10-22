class AddConferenceToStandings < ActiveRecord::Migration[7.1]
  def change
    add_column :standings, :conference, :string
  end
end
