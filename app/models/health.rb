# app/models/health.rb
class Health < ApplicationRecord
  belongs_to :player

  def manual_override_active?(date = Date.today)
    manual_override_on.present? && manual_override_on == date
  end
end
