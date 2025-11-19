class HomeController < ApplicationController
  def index
    # 1️⃣ Determine date (default: today)
    @date = params[:date] ? Date.parse(params[:date]) : Date.today

    # 2️⃣ Get the active season
    @current_season = Season.find_by(current: true)
    season_id = @current_season&.id

    # 3️⃣ Load today's games for the current season
    @todays_games = Game.where(date: @date, season_id: season_id)
                        .includes(:visitor_team, :home_team)

    # 4️⃣ Collect IDs for today's teams
    team_ids = @todays_games.pluck(:visitor_team_id, :home_team_id).flatten.uniq

    # Return early if no games today
    if team_ids.blank?
      @players_over_15_minutes = []
      @top_hit_rates = {}
      @standings = Standing.none
      return
    end

    # 5️⃣ Build player data (averages, betting info) efficiently and cache it
    @players_over_15_minutes = Rails.cache.fetch("players_over_15_minutes_#{@date}", expires_in: 15.minutes) do
      players = Player.where(team_id: team_ids).includes(box_scores: :game)

      # Collect recent box scores in bulk
      recent_box_scores = BoxScore.joins(:game)
                                  .where(games: { season_id: season_id })
                                  .where(player_id: players.ids)
                                  .where.not(minutes_played: nil)
                                  .order("games.date DESC")

      # Group last 10 and last 5 by player
      grouped_by_player = recent_box_scores.group_by(&:player_id)

      # Precompute averages for each player
      players_data = players.map do |player|
        box_scores = grouped_by_player[player.id] || []
        last_five  = box_scores.first(5)
        last_ten   = box_scores.first(10)

        next if last_five.empty?

        avg5 = compute_bulk_averages(last_five)
        avg10 = compute_bulk_averages(last_ten)

        if avg5[:minutes_played] > 15
          { player: player, averages: avg5, last_ten_averages: avg10 }
        end
      end.compact

      players_data.sort_by { |data| -data[:averages][:minutes_played] }
    end

    # 7️⃣ Standings for current season
    @standings = Standing.where(season_id: season_id)
                        .includes(:team)
                        .order(win_percentage: :desc)
  end

  def filter_duplicate_thresholds(data)
    seen_players = {}
    filtered = []
    data.each do |entry|
      pid = entry[:player].id
      next if seen_players[pid] && seen_players[pid][:hit_rate] == 100
      filtered << entry
      seen_players[pid] = entry if entry[:hit_rate] == 100
    end
    filtered
  end

  # ---------------------------------------------------------------------------
  # 📊 AVERAGE & BETTING INFO CALCULATIONS
  # ---------------------------------------------------------------------------

  def calculate_last_five_averages(player, season_id = nil)
    calculate_averages(player, 5, season_id)
  end

  def calculate_last_ten_averages(player, season_id = nil)
    calculate_averages(player, 10, season_id)
  end

  def calculate_averages(player, limit, season_id = nil)
    games = player.box_scores.includes(:game)
    games = games.where(season_id: season_id) if season_id
    games = games.where.not(minutes_played: nil).order('games.date DESC').limit(limit)

    {
      minutes_played: average_minutes(games),
      points: avg_stat(games, :points),
      rebounds: avg_stat(games, :total_rebounds),
      assists: avg_stat(games, :assists),
      three_point_field_goals: avg_stat(games, :three_point_field_goals),
      field_goals: avg_ratio(games, :field_goals, :field_goals_attempted),
      three_pointers: avg_ratio(games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: avg_ratio(games, :free_throws, :free_throws_attempted),
      plus_minus: avg_stat(games, :plus_minus),
      points_plus_assists: avg_combo(games, %i[points assists]),
      points_plus_rebounds: avg_combo(games, %i[points total_rebounds]),
      rebounds_plus_assists: avg_combo(games, %i[total_rebounds assists]),
      points_rebounds_plus_assists: avg_combo(games, %i[points total_rebounds assists])
    }
  end

  def average_minutes(games)
    valid = games.select { |g| g.minutes_played.present? }
    return 0 if valid.empty?
    total_sec = valid.sum do |g|
      m, s = g.minutes_played.split(':').map(&:to_i)
      (m * 60) + s
    end
    total_sec / 60.0 / valid.size
  end

  def avg_stat(games, stat)
    return 0 if games.empty?
    total = games.sum { |g| g.send(stat).to_f }
    total / games.size
  end

  def avg_ratio(games, made, att)
    total_made = games.sum(&made)
    total_att  = games.sum(&att)
    total_att > 0 ? (total_made.to_f / total_att).round(3) : 0
  end

  def avg_combo(games, stats)
    return 0 if games.empty?
    total = games.sum { |g| stats.sum { |s| g.send(s).to_f } }
    total / games.size
  end

  # ---------------------------------------------------------------------------
  # 🔄 SCRAPER ACTIONS
  # ---------------------------------------------------------------------------

  def update_schedule
    month = params[:month]
    Scrapers::ScheduleScraper.scrape_schedule(month)
    redirect_to root_path, notice: "#{month} schedule updated successfully."
  end

  def update_injuries
    Scrapers::InjuryScraper.scrape_and_update_injuries
    redirect_to root_path, notice: "Player injuries updated successfully."
  end

  def scrape_previous_day_games
    require 'rake'
    Rails.application.load_tasks
    Rake::Task['scrapers:box_scores'].reenable
    Rake::Task['scrapers:box_scores'].invoke
    redirect_to root_path, notice: "Box scores for yesterday's games are being scraped."
  end
end


private

def compute_bulk_averages(box_scores)
  count = box_scores.size.to_f
  {
    minutes_played: avg_minutes(box_scores),
    points: box_scores.sum(&:points).to_f / count,
    rebounds: box_scores.sum(&:total_rebounds).to_f / count,
    assists: box_scores.sum(&:assists).to_f / count,
    three_point_field_goals: box_scores.sum(&:three_point_field_goals).to_f / count
    usage_pct: box_scores.sum { |b| b.usage_pct.to_f } / count,
    trb_pct:   box_scores.sum { |b| b.total_rebound_pct.to_f } / count,
    ast_pct:   box_scores.sum { |b| b.assist_pct.to_f } / count
  }
end

def avg_minutes(box_scores)
  valid = box_scores.select { |g| g.minutes_played.present? }
  return 0 if valid.empty?
  total_seconds = valid.sum do |g|
    m, s = g.minutes_played.split(':').map(&:to_i)
    (m * 60) + s
  end
  (total_seconds / 60.0 / valid.size).round(1)
end