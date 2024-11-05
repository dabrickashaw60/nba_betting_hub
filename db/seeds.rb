# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
# db/seeds.rb

teams_data = {
  "Atlanta Hawks" => "ATL",
  "Boston Celtics" => "BOS",
  "Brooklyn Nets" => "BRK",
  "Charlotte Hornets" => "CHO",
  "Chicago Bulls" => "CHI",
  "Cleveland Cavaliers" => "CLE",
  "Dallas Mavericks" => "DAL",
  "Denver Nuggets" => "DEN",
  "Detroit Pistons" => "DET",
  "Golden State Warriors" => "GSW",
  "Houston Rockets" => "HOU",
  "Indiana Pacers" => "IND",
  "Los Angeles Clippers" => "LAC",
  "Los Angeles Lakers" => "LAL",
  "Memphis Grizzlies" => "MEM",
  "Miami Heat" => "MIA",
  "Milwaukee Bucks" => "MIL",
  "Minnesota Timberwolves" => "MIN",
  "New Orleans Pelicans" => "NOP",
  "New York Knicks" => "NYK",
  "Oklahoma City Thunder" => "OKC",
  "Orlando Magic" => "ORL",
  "Philadelphia 76ers" => "PHI",
  "Phoenix Suns" => "PHO",
  "Portland Trail Blazers" => "POR",
  "Sacramento Kings" => "SAC",
  "San Antonio Spurs" => "SAS",
  "Toronto Raptors" => "TOR",
  "Utah Jazz" => "UTA",
  "Washington Wizards" => "WAS"
}

teams_data.each do |team_name, abbreviation|
  team = Team.find_by(name: team_name)
  if team
    team.update(abbreviation: abbreviation)
    puts "Updated #{team_name} abbreviation to #{abbreviation}"
  else
    puts "Team #{team_name} not found."
  end
end
