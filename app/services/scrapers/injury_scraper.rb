require 'nokogiri'
require 'open-uri'

module Scrapers
  class InjuryScraper
    INJURIES_URL = 'https://www.espn.com/nba/injuries'

    STATUS_KEYWORDS = ['Out', 'Day-To-Day', 'Out For Season', 'Healthy'].freeze
    FORCE_OUT_NAMES = ['Paul George', 'Jimmy Butler'].freeze

    def self.scrape_and_update_injuries
      doc = Nokogiri::HTML(URI.open(INJURIES_URL))

      # Locate all rows in the injuries table
      injury_rows = doc.css('.Table__TBODY .Table__TR')

      injury_rows.each do |row|
        # Extract player name
        player_name = row.at_css('.col-name a')&.text&.strip
        next unless player_name

        # Normalize player name
        normalized_name = normalize_name(player_name)

        # Extract description
        description = row.at_css('.col-desc')&.text&.strip

        # Extract status
        status = row.at_css('.col-stat span')&.text&.strip || 'Unknown'

        # Extract date
        update_date = row.at_css('.col-date')&.text&.strip
        parsed_date = update_date ? Date.parse(update_date) : Date.today

        # Match player
        player = Player.find_by('name = ? OR name = ?', player_name, normalized_name)

        if player
          health = player.health || player.build_health
          health.update(
            status: STATUS_KEYWORDS.include?(status) ? status : 'Unknown',
            description: description,
            last_update: parsed_date
          )
          puts "Updated #{player_name}: #{status} - #{description}"
        else
          puts "Player not found: #{player_name}"
        end
      end

      # FORCE OVERRIDES — ALWAYS OUT
      FORCE_OUT_NAMES.each do |forced_name|
        forced_player = Player.find_by(name: forced_name)
        next unless forced_player

        health = forced_player.health || forced_player.build_health
        health.update(
          status: 'Out',
          description: 'Manually set to Out (override)',
          last_update: Date.today
        )
        puts "Forced #{forced_name} to Out (manual override)"
      end

      # Collect scraped names
      existing_player_names = injury_rows.map do |row|
        normalize_name(row.at_css('.col-name a')&.text&.strip)
      end.compact

      # Mark players not in the scraped list as Healthy
      Player.find_each do |player|
        # Never auto-reset forced-out players
        next if FORCE_OUT_NAMES.include?(player.name)
        next if existing_player_names.include?(normalize_name(player.name))

        health = player.health || player.build_health
        health.update(
          status: 'Healthy',
          description: 'Player is healthy.',
          last_update: Date.today
        )
        puts "Marked #{player.name} as Healthy."
      end

      puts "Scraping complete. Players not found in the scrape have been marked as Healthy."
    end

    private

    # Normalize name by removing special characters
    def self.normalize_name(name)
      return '' unless name
      name.unicode_normalize(:nfkd).chars.select(&:ascii_only?).join
    end
  end
end
