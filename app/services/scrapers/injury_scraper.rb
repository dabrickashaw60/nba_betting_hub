require 'nokogiri'
require 'open-uri'

module Scrapers
  class InjuryScraper
    INJURIES_URL = 'https://www.basketball-reference.com/friv/injuries.fcgi'
  
    STATUS_KEYWORDS = ['Healthy', 'Out', 'Out For Season', 'Day To Day'].freeze
  
    def self.scrape_and_update_injuries
      doc = Nokogiri::HTML(URI.open(INJURIES_URL))
  
      # Find the table by ID
      injuries_table = doc.css('#injuries')
  
      # Iterate over each row in the table
      injuries_table.css('tbody tr').each do |row|
        player_name = row.css('th[data-stat="player"] a').text.strip
        team_name = row.css('td[data-stat="team_name"]').text.strip
        update_date = row.css('td[data-stat="date_update"]').text.strip
        description = row.css('td[data-stat="note"]').text.strip
  
        # Extract the player's status
        status = STATUS_KEYWORDS.find { |keyword| description.start_with?(keyword) } || 'Unknown'
  
        # Match player by name
        player = Player.joins(:team).find_by(name: player_name, teams: { name: team_name })
        if player
          health = player.health || player.build_health
          health.update(
            status: status,
            description: description,
            last_update: Date.parse(update_date)
          )
          puts "Updated #{player_name} (#{team_name}): #{status} - #{description}"
        else
          puts "Player not found: #{player_name} (#{team_name})"
        end
      end
  
      # Set all players not in the scraped list to Healthy
      Player.find_each do |player|
        unless injuries_table.css('tbody tr th[data-stat="player"] a').map(&:text).include?(player.name)
          if player.team.present?
            health = player.health || player.build_health
            health.update(status: 'Healthy', description: 'Player is healthy.', last_update: Date.today)
            puts "Marked #{player.name} (#{player.team.name}) as Healthy."
          else
            puts "Skipped #{player.name} because they are not associated with a team."
          end
        end
      end
  
      puts "Scraping complete. Players not found in the scrape have been marked as Healthy."
    end
  end
  
  
end
