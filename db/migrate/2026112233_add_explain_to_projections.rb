class AddExplainToProjections < ActiveRecord::Migration[6.1]
  def change
    add_column :projections, :explain, :json
  end
end