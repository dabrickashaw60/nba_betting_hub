class HomeController < ApplicationController
  def index
    @date = params[:date] ? Date.parse(params[:date]) : Date.today
    @todays_games = Game.where(date: @date).includes(:visitor_team, :home_team)

    # Get all team IDs playing today
    team_ids = @todays_games.pluck(:visitor_team_id, :home_team_id).flatten

    # Fetch players from today's games teams
    @players_over_15_minutes = Player.where(team_id: team_ids).map do |player|
      averages = calculate_last_five_averages(player)
      if averages[:minutes_played] > 15
        { player: player, averages: averages }
      end
    end.compact.sort_by { |data| -data[:averages][:minutes_played] }

    @standings = Standing.where(season: 2025).includes(:team).order(win_percentage: :desc)
  end

  def update_schedule
    month = params[:month]
    Scrapers::ScheduleScraper.scrape_schedule(month)
    redirect_to root_path, notice: "#{month} schedule updated successfully."
  end

  def average_combined_stat(games, stats)
    return 0 if games.empty?
  
    total = games.sum do |game|
      stats.sum { |stat| game.send(stat).to_f }
    end
  
    total / games.size
  end

  private

  def calculate_last_five_averages(player)
    last_five_games = player.box_scores.includes(:game).where.not(minutes_played: nil).order('games.date DESC').limit(5)

    {
      minutes_played: calculate_average_minutes(last_five_games),
      points: average_stat(last_five_games, :points),
      rebounds: average_stat(last_five_games, :total_rebounds),
      assists: average_stat(last_five_games, :assists),
      three_point_field_goals: average_stat(last_five_games, :three_point_field_goals),
      field_goals: average_ratio(last_five_games, :field_goals, :field_goals_attempted),
      three_pointers: average_ratio(last_five_games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: average_ratio(last_five_games, :free_throws, :free_throws_attempted),
      plus_minus: average_stat(last_five_games, :plus_minus),
      points_plus_assists: average_combined_stat(last_five_games, [:points, :assists]),
      points_plus_rebounds: average_combined_stat(last_five_games, [:points, :total_rebounds]),
      rebounds_plus_assists: average_combined_stat(last_five_games, [:total_rebounds, :assists]),
      points_rebounds_plus_assists: average_combined_stat(last_five_games, [:points, :total_rebounds, :assists])

    }
  end

  def calculate_average_minutes(games)
    valid_games = games.select { |game| game.minutes_played.present? }
    return 0 if valid_games.empty?

    total_seconds = valid_games.sum do |game|
      minutes, seconds = game.minutes_played.split(":").map(&:to_i)
      (minutes * 60) + seconds
    end

    total_seconds / 60.0 / valid_games.size # Return average minutes as a float
  end

  def average_stat(games, stat)
    total_stat = games.sum { |game| game.send(stat) }
    games.size > 0 ? (total_stat.to_f / games.size) : 0
  end

  def average_ratio(games, made_stat, attempted_stat)
    total_made = games.sum(&made_stat)
    total_attempted = games.sum(&attempted_stat)
    total_attempted > 0 ? (total_made.to_f / total_attempted).round(3) : 0
  end
end
