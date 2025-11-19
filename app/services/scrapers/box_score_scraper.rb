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
      basic_table_id = "box-#{team.abbreviation}-game-basic"
      advanced_table_id = "box-#{team.abbreviation}-game-advanced"

      basic_rows = parsed_page.css("##{basic_table_id} tbody tr")
      advanced_rows = parsed_page.css("##{advanced_table_id} tbody tr")

      if basic_rows.empty?
        puts "Box score table not found for team #{team.name} (#{basic_table_id})"
        return
      end

      puts "Found box score tables for #{team.name}"

      # Build a lookup hash for advanced stats keyed by player name
      advanced_data = {}
      advanced_rows.each do |row|
        player_name = row.at_css('th[data-stat="player"] a')&.text
        next unless player_name

        advanced_data[player_name] = {
          true_shooting_pct: safe_to_f(row.at_css('td[data-stat="ts_pct"]')&.text),
          effective_fg_pct: safe_to_f(row.at_css('td[data-stat="efg_pct"]')&.text),
          three_point_attempt_rate: safe_to_f(row.at_css('td[data-stat="fg3a_per_fga_pct"]')&.text),
          free_throw_rate: safe_to_f(row.at_css('td[data-stat="fta_per_fga_pct"]')&.text),
          offensive_rebound_pct: safe_to_f(row.at_css('td[data-stat="orb_pct"]')&.text),
          defensive_rebound_pct: safe_to_f(row.at_css('td[data-stat="drb_pct"]')&.text),
          total_rebound_pct: safe_to_f(row.at_css('td[data-stat="trb_pct"]')&.text),
          assist_pct: safe_to_f(row.at_css('td[data-stat="ast_pct"]')&.text),
          steal_pct: safe_to_f(row.at_css('td[data-stat="stl_pct"]')&.text),
          block_pct: safe_to_f(row.at_css('td[data-stat="blk_pct"]')&.text),
          turnover_pct: safe_to_f(row.at_css('td[data-stat="tov_pct"]')&.text),
          usage_pct: safe_to_f(row.at_css('td[data-stat="usg_pct"]')&.text),
          offensive_rating: safe_to_i(row.at_css('td[data-stat="off_rtg"]')&.text),
          defensive_rating: safe_to_i(row.at_css('td[data-stat="def_rtg"]')&.text),
          box_plus_minus: safe_to_f(row.at_css('td[data-stat="bpm"]')&.text)
        }
      end

      # Loop through the basic table and merge advanced data
      basic_rows.each do |row|
        player_name = row.at_css('th[data-stat="player"] a')&.text
        next unless player_name

        did_not_play = row.at_css('td[data-stat="reason"]')&.text
        next if %w[Did\ Not\ Play Inactive].include?(did_not_play)

        minutes_played_text = row.at_css('td[data-stat="mp"]')&.text
        minutes_played_seconds = convert_minutes_to_seconds(minutes_played_text)
        next if minutes_played_seconds == 0

        player = Player.find_by(name: player_name)
        unless player
          puts "Skipping unknown player #{player_name}"
          next
        end

        # Team correction logic (same as before)
        if player.team_id != team.id
          old_team = player.team&.name || "Unknown"
          player.update(team_id: team.id)
          puts "Updated team for #{player.name} (#{old_team} → #{team.name})"
        end

        # Basic stats
        box_score_data = {
          game: @game,
          team: team,
          player: player,
          season_id: @game.season_id,
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

        # Merge in advanced stats if available
        if advanced_data[player_name]
          box_score_data.merge!(advanced_data[player_name])
        else
          puts "⚠️ No advanced stats found for #{player_name}"
        end

        # Save
        box_score = BoxScore.find_or_initialize_by(game: @game, team: team, player: player)
        box_score.assign_attributes(box_score_data)
        if box_score.save
          puts "Saved box score (with advanced) for #{player_name}"
        else
          puts "❌ Failed to save box score for #{player_name}: #{box_score.errors.full_messages.join(', ')}"
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
