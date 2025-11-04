class AddAssistPctAndReboundPctToProjections < ActiveRecord::Migration[6.1]
  def change
    add_column :projections, :assist_pct, :float
    add_column :projections, :rebound_pct, :float
  end
end
