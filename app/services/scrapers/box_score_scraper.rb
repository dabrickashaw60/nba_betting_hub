module Scrapers
  class BoxScoreScraper
    def initialize(game)
      @game = game
      @url = "https://www.basketball-reference.com/boxscores/#{@game.date.strftime("%Y%m%d")}0#{@game.home_team.abbreviation}.html"
      puts "Initialized scraper for Game ID: #{@game.id} with URL: #{@url}"
    end

    def scrape_box_score
      response = HTTParty.get(@url)
      if response.success?
        parsed_page = Nokogiri::HTML(response.body)
        puts "Successfully fetched page for Game ID: #{@game.id}"

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
    
        player = Player.find_by(name: player_name)
        unless player
          puts "Player #{player_name} not found in database, skipping."
          next
        end
    
        box_score_data = {
          game: @game,
          team: team,
          player: player,
          minutes_played: row.at_css('td[data-stat="mp"]')&.text,
          field_goals: row.at_css('td[data-stat="fg"]')&.text.to_i,
          field_goals_attempted: row.at_css('td[data-stat="fga"]')&.text.to_i,
          field_goal_percentage: row.at_css('td[data-stat="fg_pct"]')&.text.to_f,
          three_point_field_goals: row.at_css('td[data-stat="fg3"]')&.text.to_i,
          three_point_field_goals_attempted: row.at_css('td[data-stat="fg3a"]')&.text.to_i,
          three_point_percentage: row.at_css('td[data-stat="fg3_pct"]')&.text.to_f,
          free_throws: row.at_css('td[data-stat="ft"]')&.text.to_i,
          free_throws_attempted: row.at_css('td[data-stat="fta"]')&.text.to_i,
          free_throw_percentage: row.at_css('td[data-stat="ft_pct"]')&.text.to_f,
          offensive_rebounds: row.at_css('td[data-stat="orb"]')&.text.to_i,
          defensive_rebounds: row.at_css('td[data-stat="drb"]')&.text.to_i,
          total_rebounds: row.at_css('td[data-stat="trb"]')&.text.to_i,
          assists: row.at_css('td[data-stat="ast"]')&.text.to_i,
          steals: row.at_css('td[data-stat="stl"]')&.text.to_i,
          blocks: row.at_css('td[data-stat="blk"]')&.text.to_i,
          turnovers: row.at_css('td[data-stat="tov"]')&.text.to_i,
          personal_fouls: row.at_css('td[data-stat="pf"]')&.text.to_i,
          points: row.at_css('td[data-stat="pts"]')&.text.to_i,
          game_score: row.at_css('td[data-stat="game_score"]')&.text.to_f,
          plus_minus: row.at_css('td[data-stat="plus_minus"]')&.text.to_f
        }
    
        box_score = BoxScore.find_or_initialize_by(game: @game, team: team, player: player)
        box_score.assign_attributes(box_score_data)
    
        if box_score.save
          puts "Saved box score for player #{player_name} in Game ID: #{@game.id}"
        else
          puts "Failed to save box score for player #{player_name} in Game ID: #{@game.id}: #{box_score.errors.full_messages.join(', ')}"
        end
      end
    end    
    
  end
end
