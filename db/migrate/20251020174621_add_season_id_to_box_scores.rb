class AddSeasonIdToBoxScores < ActiveRecord::Migration[6.1]
  def change
    add_column :box_scores, :season_id, :integer
  end
end
