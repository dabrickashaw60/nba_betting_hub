require "nokogiri"
require "open-uri"

module Scrapers
  class TeamAdvancedStatsScraper
    BASE_URL = "https://www.basketball-reference.com/leagues/"

    def initialize(season)
      @season = season
      @year = season.end_year
      @url = "#{BASE_URL}NBA_#{@year}.html"
    end

    def scrape
      puts "=============================="
      puts " Team Advanced Stats Scraper"
      puts " Season: #{@season.name}"
      puts " URL: #{@url}"
      puts "=============================="

      begin
        doc = Nokogiri::HTML(URI.open(@url))
      rescue => e
        puts "❌ Failed to fetch URL: #{@url}"
        puts "Error: #{e.message}"
        return
      end

      table = doc.at_css("#advanced-team")

      unless table
        puts "❌ Could not find table #advanced-team on the page!"
        return
      end

      puts "✔ Found #advanced-team table"
      puts "------------------------------"

      rows = table.css("tbody tr")

      puts "Found #{rows.size} rows in the table"
      puts "------------------------------"

      rows.each do |row|
        # Team name is in <td data-stat="team"><a>Team Name</a>
        team_name = row.at_css("td[data-stat='team'] a")&.text

        if team_name.nil? || team_name.strip.empty?
          puts "Skipping row — no team name"
          next
        end

        puts "Processing team: #{team_name}"

        # Match team name EXACTLY in DB
        team = Team.find_by(name: team_name)

        if team.nil?
          puts "  ❌ No matching Team in DB for: #{team_name}"
          next
        else
          puts "  ✔ Matched DB team: #{team.name}"
        end

        stats = extract_stats(row)

        puts "  Stats extracted: #{stats.keys.size} fields"
        puts "  Updating TeamAdvancedStat record..."

        record = TeamAdvancedStat.find_or_initialize_by(
          team: team,
          season: @season
        )
        record.stats = stats
        record.save!

        puts "  ✔ Saved"
        puts "------------------------------"
      end

      puts "DONE — Team Advanced Stats updated."
      puts "=============================="
    end

    private

    def extract_stats(row)
      stats = {}

      row.css("td").each do |td|
        key = td["data-stat"]        # ex: "mov", "srs", "efg_pct", etc
        val = td.text.strip

        # Convert numeric strings (incl. floats) to float
        if val =~ /^-?\d+(\.\d+)?$/
          val = val.to_f
        end

        stats[key] = val
      end

      stats
    end
  end
end
