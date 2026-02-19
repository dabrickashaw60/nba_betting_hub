# db/migrate/20260219123456_add_manual_override_to_healths.rb
class AddManualOverrideToHealths < ActiveRecord::Migration[6.1]
  def change
    add_column :healths, :manual_status, :string
    add_column :healths, :manual_description, :string
    add_column :healths, :manual_override_on, :date
  end
end
