# app/services/scrapers/player_stats_scraper.rb
module Scrapers
  class PlayerStatsScraper
    include HTTParty
    base_uri 'https://www.basketball-reference.com'

    def initialize(team_abbreviation, team_id)
      @team_abbreviation = team_abbreviation
      @team_id = team_id
    end

    # Public method to scrape stats for a single player
    def scrape_stats_for_player(player)
      puts "Attempting to find URL for #{player.name}..."
      player_url = find_player_url(player.name)

      if player_url.nil?
        puts "Warning: Could not find a valid URL for #{player.name}. Skipping."
        return false
      end

      puts "Scraping stats for #{player.name} from #{player_url}..."

      retries = 0
      begin
        response = self.class.get(player_url)

        puts "HTTP Status Code: #{response.code} for #{player.name}"
        if response.code == 429
          raise "Rate limit hit for #{player.name}. Retrying after backoff."
        elsif response.code != 200
          puts "Error: Received status code #{response.code} for #{player_url}. Skipping."
          return false
        end

        page = Nokogiri::HTML(response.body)
        stats_section = page.at_css('#div_per_game_stats')

        unless stats_section
          puts "Warning: Could not locate the per-game stats section for #{player.name}. Skipping."
          return false
        end

        stats_table = stats_section.at_css('table#per_game_stats')
        unless stats_table
          puts "Warning: Could not locate the per-game stats table within #div_per_game_stats for #{player.name}."
          return false
        end

        stats_row = stats_table.css('tbody tr').find do |row|
          season_link = row.at_css('th[data-stat="year_id"] a')
          season_link&.text == "2024-25"
        end

        if stats_row.nil?
          available_years = stats_table.css('tbody tr th[data-stat="year_id"] a').map(&:text)
          puts "No 2025 stats found for #{player.name}. Available years: #{available_years.join(', ')}"
          return false
        end

        new_stats = extract_stats(stats_row)
        update_and_log_stats(player, new_stats)
        true
      rescue => e
        if e.message.include?("Rate limit hit") && retries < 5
          retries += 1
          backoff_time = 2**retries # Exponential backoff: 2, 4, 8, 16, 32 seconds
          puts "Rate limited. Retrying in #{backoff_time} seconds..."
          sleep(backoff_time)
          retry
        else
          puts "Error processing stats for player: #{player.name}. Error: #{e.message}"
          false
        end
      end
    end

    private

    def find_player_url(player_name)
      special_urls = {
        "Clint Capela" => "https://www.basketball-reference.com/players/c/capelca01.html"
      }

      if special_urls.key?(player_name)
        puts "Found special URL for #{player_name}: #{special_urls[player_name]}"
        return special_urls[player_name]
      end

      normalized_name = normalize_name(player_name)
      first_name, last_name = normalized_name.split
      last_name_part = last_name[0, 5].downcase
      first_name_part = first_name[0, 2].downcase

      (1..5).each do |suffix|
        formatted_suffix = format('%02d', suffix)
        url = "https://www.basketball-reference.com/players/#{last_name[0].downcase}/#{last_name_part}#{first_name_part}#{formatted_suffix}.html"

        response = self.class.get(url)
        page = Nokogiri::HTML(response.body)
        player_name_in_page = page.at_css('#info #meta h1 span')&.text

        return url if player_name_in_page&.downcase == player_name.downcase
      end

      nil
    end

    def normalize_name(name)
      I18n.transliterate(name)
    end

    def extract_stats(stats_row)
      {
        season: 2025,
        games_played: stats_row.at_css('td[data-stat="games"]')&.text.to_i,
        games_started: stats_row.at_css('td[data-stat="games_started"]')&.text.to_i,
        minutes_per_game: stats_row.at_css('td[data-stat="mp_per_g"]')&.text.to_f,
        field_goals_per_game: stats_row.at_css('td[data-stat="fg_per_g"]')&.text.to_f,
        field_goals_attempted_per_game: stats_row.at_css('td[data-stat="fga_per_g"]')&.text.to_f,
        field_goal_percentage: stats_row.at_css('td[data-stat="fg_pct"]')&.text.to_f,
        three_pointers_per_game: stats_row.at_css('td[data-stat="fg3_per_g"]')&.text.to_f,
        three_pointers_attempted_per_game: stats_row.at_css('td[data-stat="fg3a_per_g"]')&.text.to_f,
        three_point_percentage: stats_row.at_css('td[data-stat="fg3_pct"]')&.text.to_f,
        two_pointers_per_game: stats_row.at_css('td[data-stat="fg2_per_g"]')&.text.to_f,
        two_pointers_attempted_per_game: stats_row.at_css('td[data-stat="fg2a_per_g"]')&.text.to_f,
        two_point_percentage: stats_row.at_css('td[data-stat="fg2_pct"]')&.text.to_f,
        free_throws_per_game: stats_row.at_css('td[data-stat="ft_per_g"]')&.text.to_f,
        free_throws_attempted_per_game: stats_row.at_css('td[data-stat="fta_per_g"]')&.text.to_f,
        free_throw_percentage: stats_row.at_css('td[data-stat="ft_pct"]')&.text.to_f,
        offensive_rebounds_per_game: stats_row.at_css('td[data-stat="orb_per_g"]')&.text.to_f,
        defensive_rebounds_per_game: stats_row.at_css('td[data-stat="drb_per_g"]')&.text.to_f,
        total_rebounds_per_game: stats_row.at_css('td[data-stat="trb_per_g"]')&.text.to_f,
        assists_per_game: stats_row.at_css('td[data-stat="ast_per_g"]')&.text.to_f,
        steals_per_game: stats_row.at_css('td[data-stat="stl_per_g"]')&.text.to_f,
        blocks_per_game: stats_row.at_css('td[data-stat="blk_per_g"]')&.text.to_f,
        turnovers_per_game: stats_row.at_css('td[data-stat="tov_per_g"]')&.text.to_f,
        personal_fouls_per_game: stats_row.at_css('td[data-stat="pf_per_g"]')&.text.to_f,
        points_per_game: stats_row.at_css('td[data-stat="pts_per_g"]')&.text.to_f
      }
    end

    def update_and_log_stats(player, new_stats)
      player_stat = PlayerStat.find_or_initialize_by(player_id: player.id, season: 2025)
      previous_stats = player_stat.attributes.symbolize_keys.slice(*new_stats.keys)

      updated_fields = new_stats.each_with_object({}) do |(field, new_value), changes|
        old_value = previous_stats[field]
        if old_value != new_value
          changes[field] = { old: old_value, new: new_value }
        end
      end

      player_stat.assign_attributes(new_stats)
      player_stat.save!

      if updated_fields.empty?
        puts "No changes for #{player.name}. Stats remain the same."
      else
        puts "Updated stats for #{player.name}:"
        updated_fields.each do |field, values|
          puts "  - #{field.to_s.humanize}: #{values[:old]} -> #{values[:new]}"
        end
      end
    end
  end
end
