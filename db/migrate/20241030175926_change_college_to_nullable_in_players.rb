class ChangeCollegeToNullableInPlayers < ActiveRecord::Migration[7.1]
  def change
    change_column_null :players, :college, true
  end
end
