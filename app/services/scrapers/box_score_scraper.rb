# app/services/scrapers/box_score_scraper.rb
module Scrapers
  class BoxScoreScraper
    def initialize(game)
      @game = game
      @url = "https://www.basketball-reference.com/boxscores/#{@game.date.strftime("%Y%m%d")}0#{@game.home_team.abbreviation}.html"
      puts "Initialized scraper for Game ID: #{@game.id} with URL: #{@url}"

      # Warn if season_id is missing on the game
      if @game.season_id.nil?
        puts "⚠️  WARNING: Game ID #{@game.id} (#{@game.date}) has no season_id set!"
      end
    end

    def scrape_box_score
      response = HTTParty.get(@url)
      if response.success?
        puts "Successfully fetched page for Game ID: #{@game.id}. Status code: #{response.code}"
        parsed_page = Nokogiri::HTML(response.body)

        puts "Parsing box scores for Game ID: #{@game.id}"
        parse_team_box_score(parsed_page, @game.visitor_team)
        parse_team_box_score(parsed_page, @game.home_team)
        puts "Finished parsing and saving box scores for Game ID: #{@game.id}"
        true
      else
        puts "Failed to fetch page for Game ID: #{@game.id}. Status code: #{response.code}"
        false
      end
    end

    private

    def parse_team_box_score(parsed_page, team)
      table_id = "box-#{team.abbreviation}-game-basic"
      team_box_score_table = parsed_page.css("##{table_id} tbody tr")

      if team_box_score_table.empty?
        puts "Box score table not found for team #{team.name} in Game ID: #{@game.id} with table ID #{table_id}"
      else
        puts "Found box score table for team #{team.name} with table ID #{table_id}"
      end

      team_box_score_table.each do |row|
        player_name = row.at_css('th[data-stat="player"] a')&.text
        next unless player_name

        # Skip rows where the player "Did Not Play" or "Inactive"
        did_not_play = row.at_css('td[data-stat="reason"]')&.text
        if did_not_play == "Did Not Play" || did_not_play == "Inactive"
          puts "Skipping player #{player_name} for Game ID: #{@game.id} - Reason: #{did_not_play}"
          next
        end

        # Skip players with 0 minutes
        minutes_played_text = row.at_css('td[data-stat="mp"]')&.text
        minutes_played_seconds = convert_minutes_to_seconds(minutes_played_text)
        if minutes_played_seconds == 0
          puts "Skipping player #{player_name} for Game ID: #{@game.id} - Played 0 minutes"
          next
        end

        player = Player.find_by(name: player_name)
        unless player
          puts "Player #{player_name} not found in database, skipping."
          next
        end

        # --- Team correction logic ---
        if team.present?
          if player.team_id.nil?
            puts "Assigning #{player.name} to #{team.name}"
            player.update!(team_id: team.id)
          elsif player.team_id != team.id
            old_team = player.team&.name || "Unknown"
            puts "Player #{player.name} has switched teams (#{old_team} → #{team.name})"
            player.update!(team_id: team.id)

            File.open(Rails.root.join('log', 'transactions.log'), 'a') do |f|
              f.puts "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] #{player.name}: #{old_team} → #{team.name}"
            end
          end
        end
        # ------------------------------

        # Prepare box score data with NaN-safe conversions
        box_score_data = {
          game: @game,
          team: team,
          player: player,
          season_id: @game.season_id, # ✅ Always include the correct season_id
          minutes_played: minutes_played_text,
          field_goals: safe_to_i(row.at_css('td[data-stat="fg"]')&.text),
          field_goals_attempted: safe_to_i(row.at_css('td[data-stat="fga"]')&.text),
          field_goal_percentage: safe_to_f(row.at_css('td[data-stat="fg_pct"]')&.text),
          three_point_field_goals: safe_to_i(row.at_css('td[data-stat="fg3"]')&.text),
          three_point_field_goals_attempted: safe_to_i(row.at_css('td[data-stat="fg3a"]')&.text),
          three_point_percentage: safe_to_f(row.at_css('td[data-stat="fg3_pct"]')&.text),
          free_throws: safe_to_i(row.at_css('td[data-stat="ft"]')&.text),
          free_throws_attempted: safe_to_i(row.at_css('td[data-stat="fta"]')&.text),
          free_throw_percentage: safe_to_f(row.at_css('td[data-stat="ft_pct"]')&.text),
          offensive_rebounds: safe_to_i(row.at_css('td[data-stat="orb"]')&.text),
          defensive_rebounds: safe_to_i(row.at_css('td[data-stat="drb"]')&.text),
          total_rebounds: safe_to_i(row.at_css('td[data-stat="trb"]')&.text),
          assists: safe_to_i(row.at_css('td[data-stat="ast"]')&.text),
          steals: safe_to_i(row.at_css('td[data-stat="stl"]')&.text),
          blocks: safe_to_i(row.at_css('td[data-stat="blk"]')&.text),
          turnovers: safe_to_i(row.at_css('td[data-stat="tov"]')&.text),
          personal_fouls: safe_to_i(row.at_css('td[data-stat="pf"]')&.text),
          points: safe_to_i(row.at_css('td[data-stat="pts"]')&.text),
          game_score: safe_to_f(row.at_css('td[data-stat="game_score"]')&.text),
          plus_minus: safe_to_f(row.at_css('td[data-stat="plus_minus"]')&.text)
        }

        # Create or update box score
        box_score = BoxScore.find_or_initialize_by(game: @game, team: team, player: player)
        box_score.assign_attributes(box_score_data)

        if box_score.save
          puts "Saved box score for player #{player_name} (#{team.name}) in Game ID: #{@game.id}"
        else
          puts "❌ Failed to save box score for player #{player_name} in Game ID: #{@game.id}: #{box_score.errors.full_messages.join(', ')}"
        end
      end
    end

    # --------------------------------------------------
    # Utility methods
    # --------------------------------------------------

    def safe_to_i(value)
      Integer(value || 0) rescue 0
    end

    def safe_to_f(value)
      Float(value || 0.0) rescue 0.0
    end

    def convert_minutes_to_seconds(minutes_played_text)
      return 0 if minutes_played_text.blank?
      minutes, seconds = minutes_played_text.split(":").map(&:to_i)
      (minutes * 60) + (seconds || 0)
    end
  end
end
