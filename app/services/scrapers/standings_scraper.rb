# app/services/scrapers/standings_scraper.rb

module Scrapers
  class StandingsScraper
    include HTTParty
    base_uri 'https://www.basketball-reference.com'

    def scrape
      page = fetch_page('/leagues/NBA_2026_standings.html')
      parse_standings(page)
    end

    private

    def fetch_page(path)
      response = self.class.get(path)
      Nokogiri::HTML(response.body)
    end

    def parse_standings(page)
      # Eastern Conference standings
      page.css('#confs_standings_E tbody tr').each do |row|
        team_name = row.at_css('a')&.text
        next unless team_name

        team = Team.find_or_create_by(name: team_name)
        standings_record = team.standings.find_or_initialize_by(season: 2025)

        standings_record.assign_attributes(
          wins: row.css('td[data-stat="wins"]').text.to_i,
          losses: row.css('td[data-stat="losses"]').text.to_i,
          win_percentage: row.css('td[data-stat="win_loss_pct"]').text.to_f,
          games_behind: row.css('td[data-stat="gb"]').text,
          points_per_game: row.css('td[data-stat="pts_per_g"]').text.to_f,
          opponent_points_per_game: row.css('td[data-stat="opp_pts_per_g"]').text.to_f,
          srs: row.css('td[data-stat="srs"]').text.to_f,
          conference: 'Eastern'
        )
        standings_record.save
      end

      # Western Conference standings
      page.css('#confs_standings_W tbody tr').each do |row|
        team_name = row.at_css('a')&.text
        next unless team_name

        team = Team.find_or_create_by(name: team_name)
        standings_record = team.standings.find_or_initialize_by(season: 2025)

        standings_record.assign_attributes(
          wins: row.css('td[data-stat="wins"]').text.to_i,
          losses: row.css('td[data-stat="losses"]').text.to_i,
          win_percentage: row.css('td[data-stat="win_loss_pct"]').text.to_f,
          games_behind: row.css('td[data-stat="gb"]').text,
          points_per_game: row.css('td[data-stat="pts_per_g"]').text.to_f,
          opponent_points_per_game: row.css('td[data-stat="opp_pts_per_g"]').text.to_f,
          srs: row.css('td[data-stat="srs"]').text.to_f,
          conference: 'Western'
        )
        standings_record.save
      end
    end
  end
end
