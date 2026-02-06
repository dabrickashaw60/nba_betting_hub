class HomeController < ApplicationController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today

    @current_season = Season.find_by(current: true)
    season_id = @current_season&.id

    @team_adv_by_team_id =
      if @current_season.present?
        Rails.cache.fetch("team_adv_by_team_id_#{season_id}", expires_in: 6.hours) do
          TeamAdvancedStat
            .where(season: @current_season)
            .select(:id, :team_id, :rankings)
            .index_by(&:team_id)
        end
      else
        {}
      end

    @todays_games =
      Game.where(date: @date, season_id: season_id)
          .includes(:visitor_team, :home_team)

    team_ids = @todays_games.pluck(:visitor_team_id, :home_team_id).flatten.uniq

    if team_ids.blank?
      @players_over_15_minutes = []
      @proj_by_player_id = {}
      @proj_team_totals = {}
      @top_hit_rates = {}
      @standings = Standing.none
      return
    end

    # Cache-bust when projections rerun
    proj_bust =
      ProjectionRun.where(date: @date, model_version: Projections::BaselineModel::MODEL_VERSION)
                  .maximum(:updated_at)
                  &.to_i

    # ------------------------------------------------------------
    # Projections (player-level) for this date + teams
    # ------------------------------------------------------------
    @proj_by_player_id =
      Projection.where(date: @date, team_id: team_ids)
                .select(
                  :player_id,
                  :team_id,
                  :expected_minutes,
                  :usage_pct,
                  :proj_points,
                  :proj_rebounds,
                  :proj_assists,
                  :proj_threes,
                  :rebound_pct,
                  :assist_pct
                )
                .index_by(&:player_id)


    # ------------------------------------------------------------
    # Projections (team totals) used to compute projected REB% / AST%
    # ------------------------------------------------------------
    team_totals_cache_key = "proj_team_totals_#{@date}_teams#{team_ids.sort.join('-')}_proj#{proj_bust}"

    @proj_team_totals = Rails.cache.fetch(team_totals_cache_key, expires_in: 15.minutes) do
      Projection.where(date: @date, team_id: team_ids)
                .group(:team_id)
                .pluck(
                  :team_id,
                  Arel.sql("COALESCE(SUM(proj_rebounds),0)"),
                  Arel.sql("COALESCE(SUM(proj_assists),0)")
                )
                .each_with_object({}) do |(team_id, reb_sum, ast_sum), h|
                  h[team_id] = { reb: reb_sum.to_f, ast: ast_sum.to_f }
                end
    end

    # ------------------------------------------------------------
    # Players list (cached)
    # ------------------------------------------------------------
    players_cache_key = "players_over_15_minutes_#{@date}_proj#{proj_bust}"

    @players_over_15_minutes = Rails.cache.fetch(players_cache_key, expires_in: 15.minutes) do
      players = Player.where(team_id: team_ids).includes(box_scores: :game)

      recent_box_scores =
        BoxScore.joins(:game)
                .where(games: { season_id: season_id })
                .where(player_id: players.ids)
                .where.not(minutes_played: nil)
                .order("games.date DESC")

      grouped_by_player = recent_box_scores.group_by(&:player_id)

      players_data = players.map do |player|
        box_scores = grouped_by_player[player.id] || []
        last_five  = box_scores.first(5)
        last_ten   = box_scores.first(10)

        next if last_five.empty?

        avg5  = compute_bulk_averages(last_five)
        avg10 = compute_bulk_averages(last_ten)

        next unless avg5[:minutes_played] > 15

        { player: player, averages: avg5, last_ten_averages: avg10 }
      end.compact

      players_data.sort_by { |data| -data[:averages][:minutes_played] }
    end

    @standings =
      Standing.where(season_id: season_id)
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
    date = params[:date].present? ? Date.parse(params[:date]) : Date.today

    # 1) Update injury statuses
    Scrapers::InjuryScraper.scrape_and_update_injuries

    # 2) Re-run projections for that date
    Projection.where(date: date).delete_all
    ProjectionRun.where(date: date, model_version: Projections::BaselineModel::MODEL_VERSION).delete_all

    run = Projections::BaselineModel.new(date: date).run!

    redirect_to root_path(date: date),
                notice: "Player injuries updated and projections re-run (#{run.projections_count} players) for #{date.strftime("%m/%d/%Y")}."
  rescue => e
    Rails.logger.error "[update_injuries] Failed: #{e.class}: #{e.message}"
    redirect_to root_path(date: (params[:date] rescue nil)),
                alert: "Injury update/projection run failed: #{e.message}"
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

  mins = average_minutes_seconds(box_scores)

  {
    minutes_played: mins[:float],
    minutes_display: mins[:mmss],
    points: box_scores.sum(&:points).to_f / count,
    rebounds: box_scores.sum(&:total_rebounds).to_f / count,
    assists: box_scores.sum(&:assists).to_f / count,
    three_point_field_goals: box_scores.sum(&:three_point_field_goals).to_f / count,
    usage_pct: box_scores.sum { |b| b.usage_pct.to_f } / count,
    trb_pct:   box_scores.sum { |b| b.total_rebound_pct.to_f } / count,
    ast_pct:   box_scores.sum { |b| b.assist_pct.to_f } / count
  }
end


def avg_minutes(box_scores)
  valid_games = box_scores.select { |g| g.minutes_played.present? }
  return "00:00" if valid_games.empty?

  total_seconds = valid_games.sum do |g|
    m, s = g.minutes_played.split(":").map(&:to_i)
    (m * 60) + s
  end

  avg_seconds = total_seconds / valid_games.size
  minutes = avg_seconds / 60
  seconds = avg_seconds % 60

  format("%02d:%02d", minutes, seconds)
end

def average_minutes_seconds(box_scores)
  valid = box_scores.select { |g| g.minutes_played.present? }
  return { float: 0.0, mmss: "00:00" } if valid.empty?

  total_seconds = valid.sum do |g|
    m, s = g.minutes_played.split(":").map(&:to_i)
    (m * 60) + s
  end

  avg_seconds = total_seconds / valid.size.to_f

  minutes = (avg_seconds / 60).floor
  seconds = (avg_seconds % 60).round

  # Handle rare rounding issue
  if seconds == 60
    minutes += 1
    seconds = 0
  end

  {
    float: avg_seconds / 60.0,
    mmss: format("%02d:%02d", minutes, seconds)
  }
end
