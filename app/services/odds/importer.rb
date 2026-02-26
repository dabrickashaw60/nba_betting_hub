module Odds
  class Importer
    PROVIDER = "Draft Kings".freeze
    TZ = "America/New_York".freeze

    def self.import_espn!(date: Date.today)
      rows = Scrapers::OddsScraper.scrape(date: date)

      imported = 0
      skipped  = 0

      rows.each do |r|
        # Scraper already normalizes ESPN abbreviations to match DB
        home_abbrev = r[:home_abbrev]
        away_abbrev = r[:away_abbrev]

        home_team = Team.find_by(abbreviation: home_abbrev)
        away_team = Team.find_by(abbreviation: away_abbrev)

        unless home_team && away_team
          Rails.logger.warn(
            "[OddsImporter] TEAM NOT FOUND away=#{away_abbrev} home=#{home_abbrev} " \
            "home_found=#{!home_team.nil?} away_found=#{!away_team.nil?}"
          )
          skipped += 1
          next
        end

        # ESPN gives start_time_utc; your games.date is stored as local (ET) date
        start_local = r[:start_time_utc].in_time_zone(TZ)
        local_date  = start_local.to_date

        game = Game.find_by(
          date: local_date,
          home_team_id: home_team.id,
          visitor_team_id: away_team.id
        )

        unless game
          Rails.logger.warn(
            "[OddsImporter] NO GAME MATCH #{away_abbrev} @ #{home_abbrev} " \
            "local_date=#{local_date} start_local=#{start_local}"
          )
          skipped += 1
          next
        end

        odd = GameOdd.find_or_initialize_by(game_id: game.id, provider: PROVIDER)

        odd.assign_attributes(
          start_time_utc: r[:start_time_utc],
          pulled_at: Time.current,
          home_spread: r[:home_spread],
          away_spread: r[:away_spread],
          total: r[:total],
          home_ml: ml_to_i(r[:home_ml]),
          away_ml: ml_to_i(r[:away_ml])
        )

        odd.save!
        imported += 1

        Rails.logger.info "[OddsImporter] SAVED game_id=#{game.id} #{away_abbrev} @ #{home_abbrev}"
      end

      Rails.logger.info "[OddsImporter] ESPN import complete imported=#{imported} skipped=#{skipped} date_param=#{date}"
      { imported: imported, skipped: skipped }
    end

    def self.ml_to_i(val)
      s = val.to_s.strip
      return nil if s.empty?
      s.to_i
    end
    private_class_method :ml_to_i
  end
end