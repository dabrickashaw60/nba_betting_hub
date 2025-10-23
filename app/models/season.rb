class Season < ApplicationRecord
  def end_year
    start_date.year + 1
  end
end
