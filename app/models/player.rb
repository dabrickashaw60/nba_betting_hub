class Player < ApplicationRecord
  belongs_to :team, optional: true
  has_many :player_stats, dependent: :destroy
  has_many :box_scores
  has_one :health, dependent: :destroy


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
    "Nikola Jokić" => "https://www.basketball-reference.com/req/202106291/images/headshots/jokicni01.jpg",
    "Michael Porter Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/portemi01.jpg",
    "Brandon Boston Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/bostobr01.jpg",
    "Dennis Schröder" => "https://www.basketball-reference.com/req/202106291/images/headshots/schrode01.jpg",
    "Dario Šarić" => "https://www.basketball-reference.com/req/202106291/images/headshots/saricda01.jpg",
    "Vince Williams Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/willivi01.jpg",
    "D'Angelo Russell" => "https://www.basketball-reference.com/req/202106291/images/headshots/russeda01.jpg",
    "P.J. Washington" => "https://www.basketball-reference.com/req/202106291/images/headshots/washipj01.jpg",
    "Jaden Hardy" => "https://www.basketball-reference.com/req/202106291/images/headshots/hardyja02.jpg",
    "Cody Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/willico04.jpg",
    "Jalen Wilson" => "https://www.basketball-reference.com/req/202106291/images/headshots/wilsoja03.jpg",
    "Trey Murphy III" => "https://www.basketball-reference.com/req/202106291/images/headshots/murphtr02.jpg",
    "Dereck Lively II" => "https://www.basketball-reference.com/req/202106291/images/headshots/livelde01.jpg",
    "Harrison Barnes" => "https://www.basketball-reference.com/req/202106291/images/headshots/barneha02.jpg",
    "Keldon Johnson" => "https://www.basketball-reference.com/req/202106291/images/headshots/johnske04.jpg",
    "Jalen Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/willija06.jpg",
    "Miles Bridges" => "https://www.basketball-reference.com/req/202106291/images/headshots/bridgmi02.jpg",
    "Anthony Davis" => "https://www.basketball-reference.com/req/202106291/images/headshots/davisan02.jpg",
    "Wendell Carter Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/cartewe01.jpg",
    "Cameron Johnson" => "https://www.basketball-reference.com/req/202106291/images/headshots/johnsca02.jpg",
    "Ziaire Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/willizi02.jpg",
    "Jaime Jaquez Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/jaqueja01.jpg",
    "Jabari Smith Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/smithja05.jpg",
    "Tristan Da Silva" => "https://www.basketball-reference.com/req/202106291/images/headshots/dasiltr01.jpg",
    "Gary Trent Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/trentga02.jpg",
    "A.J. Green" => "https://www.basketball-reference.com/req/202106291/images/headshots/greenaj01.jpg",
    "Maxi Kleber" => "https://www.basketball-reference.com/req/202106291/images/headshots/klebima01.jpg",
    "Andre Jackson Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/jacksan01.jpg",
    "Jalen Green" => "https://www.basketball-reference.com/req/202106291/images/headshots/greenja05.jpg",
    "Gary Payton II" => "https://www.basketball-reference.com/req/202106291/images/headshots/paytoga02.jpg",
    "Lindy Waters III" => "https://www.basketball-reference.com/req/202106291/images/headshots/waterli01.jpg",
    "Trayce Jackson-Davis" => "https://www.basketball-reference.com/req/202106291/images/headshots/jackstr02.jpg",
    "Jared Butler" => "https://www.basketball-reference.com/req/202106291/images/headshots/butleja02.jpg",
    "Marvin Bagley III" => "https://www.basketball-reference.com/req/202106291/images/headshots/baglema01.jpg",
    "Johnny Davis" => "https://www.basketball-reference.com/req/202106291/images/headshots/davisjo06.jpg",
    "Patrick Baldwin Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/baldwpa01.jpg",
    "Craig Porter Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/portecr01.jpg",
    "T.J. McConnell" => "https://www.basketball-reference.com/req/202106291/images/headshots/mccontj01.jpg",
    "KJ Martin" => "https://www.basketball-reference.com/req/202106291/images/headshots/martike04.jpg",
    "Ricky Council IV" => "https://www.basketball-reference.com/req/202106291/images/headshots/councri01.jpg",
    "Lester Quiñones" => "https://www.basketball-reference.com/req/202106291/images/headshots/quinole01.jpg",
    "Josh Green" => "https://www.basketball-reference.com/req/202106291/images/headshots/greenjo02.jpg",
    "Vasilije Micić" => "https://www.basketball-reference.com/req/202106291/images/headshots/micicva01.jpg",
    "Nick Smith Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/smithni01.jpg",
    "E.J. Liddell" => "https://www.basketball-reference.com/req/202106291/images/headshots/liddeej01.jpg",
    "Keon Johnson" => "https://www.basketball-reference.com/req/202106291/images/headshots/johnske07.jpg",
    "Armel Traoré" => "https://www.basketball-reference.com/req/202106291/images/headshots/armeltr01.jpg",
    "Jalen Hood-Schifino" => "https://www.basketball-reference.com/req/202106291/images/headshots/hoodsja01.jpg",
    "Maxwell Lewis" => "https://www.basketball-reference.com/req/202106291/images/headshots/lewisma05.jpg",
    "Bronny James" => "https://www.basketball-reference.com/req/202106291/images/headshots/jamesbr02.jpg",
    "Kevin Porter Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/porteke02.jpg",
    "Derrick Jones Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/jonesde02.jpg",
    "Cam Christie" => "https://www.basketball-reference.com/req/202106291/images/headshots/chrisca02.jpg",
    "P.J. Tucker" => "https://www.basketball-reference.com/req/202106291/images/headshots/tuckepj01.jpg",
    "Vlatko Čančar" => "https://www.basketball-reference.com/req/202106291/images/headshots/cancavl01.jpg",
    "David Duke Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/dukeda01.jpg",
    "Taylor Hendricks" => "https://www.basketball-reference.com/req/202106291/images/headshots/hendrita01.jpg",
    "Robert Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/williro04.jpg",
    "Taze Moore" => "https://www.basketball-reference.com/req/202106291/images/headshots/mooreta02.jpg",
    "Royce O'Neale" => "https://www.basketball-reference.com/req/202106291/images/headshots/onealro01.jpg",
    "Damion Lee" => "https://www.basketball-reference.com/req/202106291/images/headshots/leeda03.jpg",
    "TyTy Washington Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/washity02.jpg",
    "Tidjane Salaün" => "https://www.basketball-reference.com/req/202106291/images/headshots/salauti01.jpg",
    "GG Jackson II" => "https://www.basketball-reference.com/req/202106291/images/headshots/jacksgg01.jpg",
    "Terrence Shannon Jr." => "https://www.basketball-reference.com/req/202106291/images/headshots/shannte01.jpg",
    "Julian Champagnie" => "https://www.basketball-reference.com/req/202106291/images/headshots/champju02.jpg",
    "Kenrich Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/willike04.jpg",
    "Jordan Miller" => "https://www.basketball-reference.com/req/202106291/images/headshots/millejo02.jpg",
    "Jeremiah Robinson-Earl" => "https://www.basketball-reference.com/req/202106291/images/headshots/robinje02.jpg",
    "Jaden McDaniels" => "https://www.basketball-reference.com/req/202106291/images/headshots/mcdanja02.jpg",
    "Mark Williams" => "https://www.basketball-reference.com/req/202106291/images/headshots/willima07.jpg"

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
