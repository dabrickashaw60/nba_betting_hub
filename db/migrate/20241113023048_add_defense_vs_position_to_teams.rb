class AddDefenseVsPositionToTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :defense_vs_position, :json
  end
end
