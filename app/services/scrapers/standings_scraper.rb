module Scrapers
  class StandingsScraper
    include HTTParty
    base_uri 'https://www.basketball-reference.com'

    def initialize(season_id)
      @season = Season.find(season_id)
    end

    def scrape
      # Build dynamic URL for this season
      page = fetch_page("/leagues/NBA_#{@season.end_year}_standings.html")
      parse_standings(page)
    end

    private

    def fetch_page(path)
      response = self.class.get(path)
      Nokogiri::HTML(response.body)
    end

    def parse_standings(page)
      %w[E W].each do |conf|
        conference_name = conf == "E" ? "Eastern" : "Western"

        page.css("#confs_standings_#{conf} tbody tr").each do |row|
          team_name = row.at_css('a')&.text
          next unless team_name

          team = Team.find_or_create_by(name: team_name)
          standings_record = team.standings.find_or_initialize_by(season_id: @season.id)

          standings_record.assign_attributes(
            wins:  row.css('td[data-stat="wins"]').text.to_i,
            losses: row.css('td[data-stat="losses"]').text.to_i,
            win_percentage: row.css('td[data-stat="win_loss_pct"]').text.to_f,
            games_behind: row.css('td[data-stat="gb"]').text,
            points_per_game: row.css('td[data-stat="pts_per_g"]').text.to_f,
            opponent_points_per_game: row.css('td[data-stat="opp_pts_per_g"]').text.to_f,
            srs: row.css('td[data-stat="srs"]').text.to_f,
            conference: conference_name
          )

          standings_record.save!
        end
      end
    end
  end
end
