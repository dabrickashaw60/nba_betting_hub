class AddCountryOfBirthToPlayers < ActiveRecord::Migration[7.1]
  def change
    add_column :players, :country_of_birth, :string
  end
end
