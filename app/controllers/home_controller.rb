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

    # 5️⃣ Build player data (averages, betting info)
    @players_over_15_minutes = Player.where(team_id: team_ids).map do |player|
      last_five_averages = calculate_last_five_averages(player, season_id)
      last_ten_averages  = calculate_last_ten_averages(player, season_id)
      betting_info       = calculate_betting_info(player, 10, season_id)

      if last_five_averages[:minutes_played] > 15
        {
          player: player,
          averages: last_five_averages,
          last_ten_averages: last_ten_averages,
          betting_info: betting_info
        }
      end
    end.compact.sort_by { |data| -data[:averages][:minutes_played] }

    # 6️⃣ Build top hit rates (props / best lines)
    @top_hit_rates = calculate_top_hit_rates(team_ids, season_id)

    # Add last 10 averages per player for each stat key
    @top_hit_rates.each do |stat_key, rates|
      rates.each do |rate|
        player_last_ten = calculate_last_ten_averages(rate[:player], season_id)
        rate[:last_ten_averages] = player_last_ten
        rate[:last_ten_average] = case stat_key
                                  when :points then player_last_ten[:points]
                                  when :three_point_field_goals then player_last_ten[:three_point_field_goals]
                                  when :total_rebounds then player_last_ten[:rebounds]
                                  when :assists then player_last_ten[:assists]
                                  else nil
                                  end
      end
    end

    # 7️⃣ Standings for current season
    @standings = Standing.where(season_id: season_id)
                         .includes(:team)
                         .order(win_percentage: :desc)
  end

  # ---------------------------------------------------------------------------
  # 🧮 HIT RATE CALCULATIONS
  # ---------------------------------------------------------------------------

  def calculate_top_hit_rates(team_ids, season_id = nil)
    stats = %i[points three_point_field_goals total_rebounds assists]
    thresholds = {
      points: [30, 25, 20, 15, 10],
      three_point_field_goals: [5, 4, 3, 2, 1],
      total_rebounds: [10, 8, 6, 4],
      assists: [10, 8, 6, 4]
    }

    players = Player.where(team_id: team_ids)

    stats.each_with_object({}) do |stat, result|
      result[stat] = players.map do |player|
        calculate_stat_hit_rate(player, stat, thresholds[stat], season_id)
      end.flatten.compact

      result[stat].select! { |data| data[:hit_rate] >= 80 }
      result[stat] = filter_duplicate_thresholds(result[stat])
      result[stat].sort_by! { |data| [-data[:best_threshold], -data[:hit_rate]] }
    end
  end

  def calculate_stat_hit_rate(player, stat, thresholds, season_id = nil)
    recent_games = player.box_scores
                         .includes(:game)
                         .where.not(minutes_played: nil)
    recent_games = recent_games.where(season_id: season_id) if season_id
    recent_games = recent_games.order('games.date DESC').limit(10)

    thresholds.map do |threshold|
      hits = recent_games.count { |g| g.send(stat).to_f >= threshold }
      hit_rate = hits.to_f / 10
      next if hit_rate < 0.8

      {
        player: player,
        stat: stat,
        best_threshold: threshold,
        hit_rate: (hit_rate * 100).round
      }
    end.compact
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

  def calculate_betting_info(player, limit = 10, season_id = nil)
    games = player.box_scores.includes(:game)
    games = games.where(season_id: season_id) if season_id
    games = games.where.not(minutes_played: nil).order('games.date DESC').limit(limit)

    {
      points: count_thresholds(games, :points, [10, 15, 20, 25, 30]),
      threes: count_thresholds(games, :three_point_field_goals, [1, 2, 3, 4, 5]),
      rebounds: count_thresholds(games, :total_rebounds, [4, 6, 8, 10]),
      assists: count_thresholds(games, :assists, [4, 6, 8, 10])
    }
  end

  def count_thresholds(games, stat, thresholds)
    thresholds.each_with_object({}) do |t, h|
      h[t] = games.count { |g| g.send(stat).to_f >= t }
    end
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
