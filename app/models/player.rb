class Player < ApplicationRecord
  belongs_to :team, optional: true
  has_many :player_stats, dependent: :destroy
  has_many :box_scores


  has_one :player_stat, -> { where(season: PlayerStat::SEASON) }
  
  validates :name, presence: true
  validates :from_year, :to_year, :position, :height, :weight, :birth_date, presence: true

  def profile_picture_url
    # Split the name by spaces to separate the first and last name components
    name_parts = name.split
    last_name = name_parts.last.downcase           # Use the last word as the last name
    first_name = name_parts.first.downcase         # Use the first word as the first name

    # Construct the URL
    last_name_part = last_name[0, 5]               # Take the first 5 characters of the last name
    first_name_part = first_name[0, 2]             # Take the first 2 characters of the first name
    "https://www.basketball-reference.com/req/202106291/images/headshots/#{last_name_part}#{first_name_part}01.jpg"
  end
  
end
