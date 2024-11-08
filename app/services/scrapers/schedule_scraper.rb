class Scrapers::ScheduleScraper
  BASE_URL = 'https://www.basketball-reference.com/leagues/NBA_2025_games'

  def initialize(month = nil)
    @month = month
  end

  def self.scrape_schedule(month = nil)
    new(month).scrape_schedule
  end

  def scrape_schedule
    month_path = @month ? "-#{@month.downcase}" : ""
    schedule_url = "#{BASE_URL}#{month_path}.html"

    response = HTTParty.get(schedule_url)

    if response.code == 200
      puts "Successfully accessed #{schedule_url} - Status: #{response.code}"
      parsed_page = Nokogiri::HTML(response.body)

      parsed_page.css('table#schedule tbody tr').each do |row|
        game_data = parse_row(row)
        save_game(game_data) if game_data
      end
    else
      puts "Failed to access #{schedule_url} - Status: #{response.code}"
    end
  end

  private

  def parse_row(row)
    # Parse date
    date_text = row.css('th[data-stat="date_game"] a').text.strip
    date = parse_date(date_text)

    # Parse start time and handle AM/PM format with 'p' suffix
    start_time_text = row.css('td[data-stat="game_start_time"]').text.strip
    puts "Parsing start time: #{start_time_text} for date: #{date_text}"

    start_time = if start_time_text.present?
                   begin
                     # Add "m" to make it "pm" or "am" if missing
                     formatted_time_text = start_time_text.insert(-1, 'm') unless start_time_text.downcase.include?('am') || start_time_text.downcase.include?('pm')
                     DateTime.strptime(formatted_time_text, "%I:%M%p").strftime("%H:%M:%S")
                   rescue
                     nil
                   end
                 end

    puts "Parsed start time: #{start_time}"

    # Parse team names and locate the teams in the database
    visitor_team_name = row.css('td[data-stat="visitor_team_name"] a').text.strip
    home_team_name = row.css('td[data-stat="home_team_name"] a').text.strip
    visitor_team = Team.find_by(name: visitor_team_name) || Team.find_by(abbreviation: visitor_team_name)
    home_team = Team.find_by(name: home_team_name) || Team.find_by(abbreviation: home_team_name)

    # Parse other game data
    visitor_points = row.css('td[data-stat="visitor_pts"]').text.strip.to_i
    home_points = row.css('td[data-stat="home_pts"]').text.strip.to_i

    # Parse location and other data
    arena = row.css('td[data-stat="arena_name"]').text.strip
    attendance = row.css('td[data-stat="attendance"]').text.strip.gsub(',', '').to_i
    game_duration = row.css('td[data-stat="game_duration"]').text.strip
    overtime = row.css('td[data-stat="overtimes"]').text.strip.present?

    # Ensure required data is present
    if date.nil? || visitor_team.nil? || home_team.nil? || arena.blank? || start_time.nil?
      puts "Skipping game due to missing required data: Date=#{date}, Start Time=#{start_time}, Teams=#{visitor_team_name} vs #{home_team_name}"
      return nil
    end

    {
      date: date,
      time: start_time,
      visitor_team_id: visitor_team.id,
      visitor_points: visitor_points,
      home_team_id: home_team.id,
      home_points: home_points,
      location: arena,
      attendance: attendance,
      duration: game_duration,
      overtime: overtime,
      season: 2025
    }
  rescue StandardError => e
    puts "Error parsing row with date: #{date_text} - #{e.message}"
    nil
  end

  def parse_date(date_text)
    Date.strptime(date_text, "%B %d, %Y") rescue Date.parse(date_text) rescue nil
  end

  def save_game(game_data)
    game = Game.find_or_initialize_by(
      date: game_data[:date],
      visitor_team_id: game_data[:visitor_team_id],
      home_team_id: game_data[:home_team_id]
    )

    if game.new_record? || 
       game.visitor_points != game_data[:visitor_points] || 
       game.home_points != game_data[:home_points] || 
       game.time != game_data[:time]

      game.assign_attributes(game_data)

      if game.save
        puts "Saved game: #{game.inspect}"
      else
        puts "Failed to save game: #{game.errors.full_messages.join(', ')}"
      end
    else
      puts "Game already exists and is up-to-date: #{game.inspect}"
    end
  end
end
