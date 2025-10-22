module Scrapers
  class RosterScraper
    include HTTParty
    base_uri 'https://www.basketball-reference.com'

    def initialize(team_abbreviation, team_id)
      @team_abbreviation = team_abbreviation
      @team_id = team_id
    end

    def scrape
      puts "Starting roster scrape for #{@team_abbreviation} (Team ID: #{@team_id})..."
      fetch_and_parse_roster
    end

    private

    def fetch_and_parse_roster
      response = self.class.get("/teams/#{@team_abbreviation}/2026.html")
      page = Nokogiri::HTML(response.body)

      # Debugging: Print the structure if it's Denver
      if @team_abbreviation == 'DEN'
        puts "Debugging Denver's roster page HTML structure:"
        puts page.css('div#div_roster table#roster tbody').to_html # Print out the HTML content for inspection
      end

      # Select the player rows from the roster table
      roster_table = page.css('div#div_roster table#roster tbody')
      if roster_table.empty?
        puts "Warning: No roster table found for #{@team_abbreviation}. Please check the page structure."
        return
      end

      roster_table.css('tr').each do |row|
        player_name = row.at_css('td[data-stat="player"] a')&.text
        unless player_name
          puts "Skipping row: No player name found."
          next
        end

        begin
          # Extract player details
          uniform_number_text = row.at_css('th[data-stat="number"]')&.text
          uniform_number = uniform_number_text.present? ? uniform_number_text.to_i : nil
          position = row.at_css('td[data-stat="pos"]')&.text
          height = row.at_css('td[data-stat="height"]')&.text
          weight = row.at_css('td[data-stat="weight"]')&.text.to_i
          birth_date_text = row.at_css('td[data-stat="birth_date"]')&.text
          birth_date = Date.parse(birth_date_text) rescue nil
          country_of_birth = row.at_css('td[data-stat="flag"]')&.text || ""
          college = row.at_css('td[data-stat="college"] a')&.text || ""

          # Set default values for from_year and to_year
          from_year = Player.where(name: player_name).pluck(:from_year).first || 2023 # Assume 2023 if new player
          to_year = Player.where(name: player_name).pluck(:to_year).first || 2025 # Set 2025 if blank

          # Associate the player with the current team by creating or updating the player
          player = Player.find_or_create_by(name: player_name) do |p|
            p.from_year = from_year
            p.to_year = to_year
          end

          # Update additional player details
          player.update!(
            uniform_number: uniform_number,
            position: position,
            height: height,
            weight: weight,
            birth_date: birth_date,
            country_of_birth: country_of_birth,            
            college: college,
            team_id: @team_id
          )

          puts "Added or updated player: #{player_name} on team #{@team_abbreviation}"
        rescue => e
          puts "Error processing player: #{player_name}. Error: #{e.message}"
        end
      end

      puts "Roster scraping completed for #{@team_abbreviation}."
    end
  end
end
