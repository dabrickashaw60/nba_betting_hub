require "open-uri"
require "json"
require "date"
require "time"

module Scrapers
  class OddsScraper
    SCOREBOARD_URL = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard".freeze

    # ESPN abbreviations vs your DB abbreviations
    ESPN_TO_DB_ABBREV = {
      "BKN"  => "BRK",
      "CHA"  => "CHO",
      "GS"   => "GSW",
      "NO"   => "NOP",
      "NY"   => "NYK",
      "PHX"  => "PHO",
      "SA"   => "SAS",
      "UTAH" => "UTA",
      "WSH"  => "WAS"
    }.freeze

    def self.scrape(date: Date.today)
      url = "#{SCOREBOARD_URL}?dates=#{date.strftime('%Y%m%d')}"

      raw = URI.open(
        url,
        "User-Agent" => "Mozilla/5.0",
        "Accept" => "application/json",
        "Accept-Language" => "en-US,en;q=0.9"
      ).read

      data = JSON.parse(raw)
      events = data["events"] || []

      games = []

      events.each do |event|
        competition = event.dig("competitions", 0)
        next unless competition

        competitors = competition["competitors"] || []
        home = competitors.find { |c| c["homeAway"] == "home" }
        away = competitors.find { |c| c["homeAway"] == "away" }
        next unless home && away

        odds_block = (competition["odds"]&.first || competition["pickcenter"]&.first)
        next unless odds_block

        home_abbrev = normalize_abbrev(home.dig("team", "abbreviation"))
        away_abbrev = normalize_abbrev(away.dig("team", "abbreviation"))

        # Moneyline (prefer "close", fall back to "open" if close is missing)
        home_ml = odds_block.dig("moneyline", "home", "close", "odds") ||
                  odds_block.dig("moneyline", "home", "open", "odds") ||
                  odds_block.dig("homeTeamOdds", "moneyLine") ||
                  odds_block.dig("homeTeamOdds", "moneyline")

        away_ml = odds_block.dig("moneyline", "away", "close", "odds") ||
                  odds_block.dig("moneyline", "away", "open", "odds") ||
                  odds_block.dig("awayTeamOdds", "moneyLine") ||
                  odds_block.dig("awayTeamOdds", "moneyline")

        home_spread = odds_block["spread"]
        away_spread = -home_spread.to_f

        games << {
          start_time_utc: Time.parse(competition["date"]).utc,
          home_abbrev: home_abbrev,
          away_abbrev: away_abbrev,

          # ESPN spread is the home spread
          home_spread: home_spread,
          away_spread: away_spread,

          total: odds_block["overUnder"] || odds_block["total"],

          home_ml: home_ml,
          away_ml: away_ml,

          provider: odds_block.dig("provider", "name")
        }
      end

      warn_on_unknown_abbrevs!(games)

      games
    end

    def self.scrape_and_log(date: Date.today)
      Rails.logger.info "[OddsScraper] ESPN scrape start date=#{date}"
      games = scrape(date: date)
      Rails.logger.info "[OddsScraper] ESPN games=#{games.size}"

      games.each do |g|
        Rails.logger.info(
          "[OddsScraper] #{g[:away_abbrev]} @ #{g[:home_abbrev]} " \
          "spread(home=#{g[:home_spread]}, away=#{g[:away_spread]}) " \
          "total=#{g[:total]} ml(away=#{g[:away_ml]}, home=#{g[:home_ml]}) " \
          "provider=#{g[:provider]}"
        )
      end

      games
    end

    def self.normalize_abbrev(abbrev)
      ESPN_TO_DB_ABBREV[abbrev] || abbrev
    end
    private_class_method :normalize_abbrev

    def self.warn_on_unknown_abbrevs!(games)
      known = Team.pluck(:abbreviation).compact.uniq
      unknown = games.flat_map { |g| [g[:home_abbrev], g[:away_abbrev]] }.uniq - known
      return if unknown.empty?

      Rails.logger.warn "[OddsScraper] Unknown abbreviations not in DB: #{unknown.join(', ')}"
    end
    private_class_method :warn_on_unknown_abbrevs!
  end
end