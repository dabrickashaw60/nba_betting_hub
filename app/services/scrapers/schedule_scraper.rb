class Scrapers::ScheduleScraper
  BASE_URL = 'https://www.basketball-reference.com/leagues/NBA_2026_games'

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

      # Track what Basketball-Reference says should exist for TODAY+FUTURE
      # Only for dates present on the page we are currently scraping.
      scraped_keys_by_date = Hash.new { |h, k| h[k] = [] }

      parsed_page.css('table#schedule tbody tr').each do |row|
        game_data = parse_row(row)

        if game_data
          # Only sync TODAY+FUTURE (never past)
          if game_data[:date].present? && game_data[:date] >= Time.zone.today
            scraped_keys_by_date[game_data[:date]] << game_key(game_data)
          end

          save_game(game_data)
        end
      end

      # After scraping + saving, prune any TODAY+FUTURE games in the DB for these scraped dates
      # that no longer exist on Basketball-Reference.
      prune_future_games(scraped_keys_by_date)
    else
      puts "Failed to access #{schedule_url} - Status: #{response.code}"
    end
  end

  private

  # Stable comparison key for a game on a given date
  def game_key(game_data)
    [game_data[:date], game_data[:visitor_team_id], game_data[:home_team_id]]
  end

  # Delete DB games (today+future only) for dates we just scraped that aren't present on BRef anymore
  def prune_future_games(scraped_keys_by_date)
    return if scraped_keys_by_date.blank?

    season = Season.find_by(current: true) || Season.order(:start_date).last
    today = Time.zone.today

    dates = scraped_keys_by_date.keys.select { |d| d.present? && d >= today }.uniq
    return if dates.empty?

    require "set"
    expected_keys = scraped_keys_by_date.values.flatten(1).to_set
    
    db_games = Game
      .where(season_id: season.id, date: dates)
      .includes(:home_team, :visitor_team)

    to_delete = db_games.reject do |g|
      expected_keys.include?([g.date, g.visitor_team_id, g.home_team_id])
    end

    if to_delete.any?
      puts "🧹 Pruning #{to_delete.size} game(s) (today+future) that no longer match Basketball-Reference..."
      to_delete.each do |g|
        puts "  ❌ Deleting: #{g.date} - #{g.visitor_team.name} @ #{g.home_team.name} (id=#{g.id})"
      end

      # Use delete_all to avoid callbacks (fast). Change to destroy_all if you need callbacks.
      Game.where(id: to_delete.map(&:id)).delete_all
    else
      puts "🧹 No future games to prune for scraped date range."
    end
  end

  def parse_row(row)
    # Find the correct season based on current flag or date
    season = Season.find_by(current: true) || Season.order(:start_date).last

    # Parse date
    date_text = row.css('th[data-stat="date_game"] a').text.strip
    date = parse_date(date_text)

    # Parse start time and handle AM/PM format with 'p' suffix
    start_time_text = row.css('td[data-stat="game_start_time"]').text.strip
    puts "Parsing start time: #{start_time_text} for date: #{date_text}"

    start_time = if start_time_text.present?
                   begin
                     formatted_time_text =
                       if start_time_text.downcase.include?('am') || start_time_text.downcase.include?('pm')
                         start_time_text
                       else
                         start_time_text.insert(-1, 'm') # add 'm' if just 'a' or 'p'
                       end
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
      season_id: season&.id # ✅ use new column
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

    # Assign all scraped attributes
    game.assign_attributes(game_data)

    # ✅ Ensure the season_id is always set, even if parse_row missed it
    game.season_id ||= Season.find_by(current: true)&.id

    # ✅ Optional: auto-set game_type based on date if you want
    if game.date.present?
      if game.date.between?(Date.new(2025, 10, 20), Date.new(2026, 4, 14))
        game.game_type = "Regular"
      elsif game.date.between?(Date.new(2026, 4, 15), Date.new(2026, 6, 30))
        game.game_type = "Playoffs"
      end
    end

    # Save if new or changed
    if game.new_record? ||
       game.visitor_points != game_data[:visitor_points] ||
       game.home_points != game_data[:home_points] ||
       game.time != game_data[:time]

      if game.save
        puts "✅ Saved game: #{game.date} - #{game.home_team.name} vs #{game.visitor_team.name} (Season #{game.season_id})"
      else
        puts "⚠️ Failed to save game: #{game.errors.full_messages.join(', ')}"
      end
    else
      puts "ℹ️ Game already exists and is up-to-date: #{game.date} - #{game.home_team.name} vs #{game.visitor_team.name}"
    end
  end
end
