class Player < ApplicationRecord
  belongs_to :team, optional: true
  has_many :player_stats, dependent: :destroy
  has_many :box_scores


  has_one :player_stat, -> { where(season: PlayerStat::SEASON) }
  
  validates :name, presence: true
  validates :from_year, :to_year, :position, :height, :weight, :birth_date, presence: true

  def team_name
    team.name
  end

  def profile_picture_url

  # Define a hash of specific URLs for players with unique headshot formats
  exceptions = {
    "Jaren Jackson Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/jacksja02.jpg",
    "Scotty Pippen Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/pippesc02.jpg",
    "Brandon Miller" => "https://www.basketball-reference.com/req/202106291/images/headshots/millebr02.jpg",
    "Luka Dončić" => "https://www.basketball-reference.com/req/202106291/images/headshots/doncilu01.jpg",
    "Jalen Johnson" => "https://www.basketball-reference.com/req/202106291/images/headshots/johnsja05.jpg",
    "Jaylen Brown" => "https://www.basketball-reference.com/req/202106291/images/headshots/brownja02.jpg",
    "Clint Capela" => "https://www.basketball-reference.com/req/202106291/images/headshots/capelca01.jpg",
    "Cam Thomas" => "https://www.basketball-reference.com/req/202106291/images/headshots/thomaca02.jpg",
    "Larry Nance Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/nancela02.jpg",
    "Caleb Martin" => "https://www.basketball-reference.com/req/202106291/images/headshots/martica02.jpg",
    "Kelly Oubre Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/oubreke01.jpg",
    "Keegan Murray" => "https://www.basketball-reference.com/req/202106291/images/headshots/murrake02.jpg",
    "Tobias Harris" => "https://www.basketball-reference.com/req/202106291/images/headshots/harrito02.jpg",
    "Xavier Tillman Sr." => "https://www.basketball-reference.com/req/202106291/images/headshots/tillmxa01.jpg",
    "Nikola Vučević" => "https://www.basketball-reference.com/req/202106291/images/headshots/vucevni01.jpg",
    "Jalen Smith" => "https://www.basketball-reference.com/req/202106291/images/headshots/smithja04.jpg",
    "Tim Hardaway Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/hardati02.jpg",
    "Wendell Moore Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/moorewe01.jpg",
    "Nikola Jović" => "",
    "Jaime Jaquez Jr." => "",
    "KJ Martin" => "",
    "Ricky Council IV" => "",
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 
    "" => "", 

  }

  # If the player's name matches an exception, return the specific URL
  return exceptions[name] if exceptions.key?(name)
  
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
