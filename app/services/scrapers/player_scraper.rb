module Scrapers
  class PlayerScraper
    include HTTParty
    base_uri 'https://www.basketball-reference.com'

    def scrape
      ('a'..'z').each do |letter|
        puts "Scraping players with last names starting with '#{letter.upcase}'..."
        fetch_and_parse_players(letter)
      end
      puts "Player scraping completed for all letters."
    end

    private

    def fetch_and_parse_players(letter)
      response = self.class.get("/players/#{letter}/")
      page = Nokogiri::HTML(response.body)

      # Select player rows from the table
      page.css('div#div_players table tbody tr').each do |row|
        # Extract player data
        player_name = row.at_css('th[data-stat="player"] a')&.text
        next unless player_name # Skip if no player name

        from_year = row.at_css('td[data-stat="year_min"]')&.text.to_i
        to_year = row.at_css('td[data-stat="year_max"]')&.text.to_i
        position = row.at_css('td[data-stat="pos"]')&.text
        height = row.at_css('td[data-stat="height"]')&.text
        weight = row.at_css('td[data-stat="weight"]')&.text.to_i
        birth_date_text = row.at_css('td[data-stat="birth_date"]')&.text
        birth_date = Date.parse(birth_date_text) rescue nil
        college = row.at_css('td[data-stat="colleges"]')&.text

        # Only add players who are active in recent years (2023, 2024, or 2025)
        if [2023, 2024, 2025, 2026].include?(to_year)
          # Check for essential data and log if any is missing
          missing_data = []
          missing_data << "position" unless position.present?
          missing_data << "height" unless height.present?
          missing_data << "weight" unless weight.present?
          missing_data << "birth_date" unless birth_date.present?

          if missing_data.any?
            puts "Skipping player: #{player_name}. Missing data: #{missing_data.join(', ')}"
            next
          end

          # Use find_or_initialize_by to avoid duplicates
          player = Player.find_or_initialize_by(name: player_name)
          player.assign_attributes(
            from_year: from_year,
            to_year: to_year,
            position: position,
            height: height,
            weight: weight,
            birth_date: birth_date,
            college: college
          )

          # Save and log the result
          if player.save
            puts "Added or updated player: #{player_name}"
          else
            puts "Failed to add player: #{player_name}. Errors: #{player.errors.full_messages.join(", ")}"
          end
        end
      end
    end
  end
end
