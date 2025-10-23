class PlayersController < ApplicationController
  before_action :set_current_season
  before_action :set_team_and_player, only: [:show, :update_stats]

  # ---------------------------------------------------------------------------
  # 🧍 SHOW: Player profile, averages, next game, defense matchup
  # ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def show
  @team = Team.find(params[:team_id])
  @player = @team.players.find(params[:id])

  # --- Determine Selected Season ---
  @seasons = Season.order(start_date: :desc)
  @selected_season =
    if params[:season_id].present?
      Season.find_by(id: params[:season_id])
    else
      Season.find_by(current: true)
    end

  # Safety fallback if no season found
  unless @selected_season
    flash[:alert] = "No active season found."
    redirect_to team_path(@team) and return
  end

  season_id = @selected_season.id

  # --- Player Stats (this season only) ---
  @player_stats = @player.player_stats.where(season_id: season_id)
                                      .order(created_at: :desc)

  # --- Game Logs (this season only) ---
  @game_logs = @player.box_scores
                      .joins(:game)
                      .where(games: { season_id: season_id })
                      .where.not(minutes_played: nil)
                      .order('games.date DESC')

  # --- Last 5 and 10 Games ---
  @last_five_games = @game_logs.limit(5)
  @last_ten_games  = @game_logs.limit(10)

  # --- Build Averages ---
  @last_five_averages = build_averages(@last_five_games)
  @last_ten_averages  = build_averages(@last_ten_games)

  # --- Betting Info (Last 5 Games) ---
  @betting_info = {
    points:   count_thresholds(@last_five_games, :points, [10, 15, 20, 25, 30]),
    threes:   count_thresholds(@last_five_games, :three_point_field_goals, [1, 2, 3, 4, 5]),
    rebounds: count_thresholds(@last_five_games, :total_rebounds, [2, 4, 6, 8, 10]),
    assists:  count_thresholds(@last_five_games, :assists, [2, 4, 6, 8, 10])
  }

  # --- Next Upcoming Game (same season) ---
  @next_game = Game.where(season_id: season_id)
                   .where("date >= ?", Date.today)
                   .where("visitor_team_id = ? OR home_team_id = ?", @team.id, @team.id)
                   .order(:date)
                   .first

  if @next_game
    opponent_team_id =
      @next_game.visitor_team_id == @team.id ? @next_game.home_team_id : @next_game.visitor_team_id
    @opponent_team = Team.find(opponent_team_id)
    @defense_vs_position = @opponent_team.defense_data_for(@selected_season)
  end

end


  # ---------------------------------------------------------------------------
  # 🧩 FILTER_GAMES: for teammate-out comparison table
  # ---------------------------------------------------------------------------
  def filter_games
    @player = Player.find(params[:id])
    teammate_id = params[:teammate_id]
    filtered_teammate = Player.find_by(id: teammate_id)

    return render partial: 'game_rows', locals: { games: [], filtered_teammate: filtered_teammate } unless filtered_teammate

    # Filter by current season
    filtered_games = @player.box_scores
                            .joins(:game)
                            .where(season_id: @current_season.id)
                            .where.not(game_id: BoxScore.where(player_id: teammate_id)
                                                        .where("box_scores.team_id = ?", @player.team_id)
                                                        .select(:game_id))
                            .includes(:game)
                            .order('games.date DESC')
                            .limit(5)

    render partial: 'game_rows', locals: { games: filtered_games, filtered_teammate: filtered_teammate }
  end

  # ---------------------------------------------------------------------------
  # 🔄 UPDATE_STATS: manual scraper trigger for one player
  # ---------------------------------------------------------------------------
  def update_stats
    if @player.nil? || @team.nil?
      flash[:alert] = "Team or player not found."
      redirect_to teams_path and return
    end

    scraper = Scrapers::PlayerStatsScraper.new(@team.abbreviation, @team.id)
    if scraper.scrape_stats_for_player(@player)
      flash[:notice] = "Stats successfully updated for #{@player.name}."
    else
      flash[:alert] = "Failed to update stats for #{@player.name}."
    end

    redirect_to team_path(@team, anchor: 'player-stats')
  end

  # ---------------------------------------------------------------------------
  # 🔍 LIVE_SEARCH: autocomplete for player names
  # ---------------------------------------------------------------------------
  def live_search
    query = params[:query]
    @players = Player.joins(:team)
                     .where("players.name LIKE ?", "%#{query}%")
                     .limit(5)
    render json: @players.as_json(include: { team: { only: [:id, :name, :abbreviation] } })
  end

  # ---------------------------------------------------------------------------
  # 🧮 PRIVATE HELPERS
  # ---------------------------------------------------------------------------
  private

  def set_current_season
    @current_season = Season.find_by(current: true)
  end

  def set_team_and_player
    @team = Team.find(params[:team_id])
    @player = @team.players.find(params[:id])
  end

  def build_averages(games)
    {
      minutes_played: calculate_average_minutes(games),
      points: average_stat(games, :points),
      rebounds: average_stat(games, :total_rebounds),
      assists: average_stat(games, :assists),
      field_goals: average_ratio(games, :field_goals, :field_goals_attempted),
      three_pointers: average_ratio(games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: average_ratio(games, :free_throws, :free_throws_attempted),
      plus_minus: average_stat(games, :plus_minus),
      steals: average_stat(games, :steals),
      blocks: average_stat(games, :blocks),
      turnovers: average_stat(games, :turnovers),
      personal_fouls: average_stat(games, :personal_fouls)
    }
  end

  def average_stat(games, stat)
    return 0 if games.empty?
    games.sum(&stat).to_f / games.size
  end

  def calculate_average_minutes(games)
    valid_games = games.select { |g| g.minutes_played.present? }
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

  def average_ratio(games, made_stat, attempted_stat)
    total_made = games.sum(&made_stat)
    total_attempted = games.sum(&attempted_stat)
    if total_attempted > 0
      "#{(total_made.to_f / games.size).round(1)}/#{(total_attempted.to_f / games.size).round(1)}"
    else
      "0.0 / 0.0"
    end
  end

  def count_thresholds(games, stat, thresholds)
    thresholds.map { |t| games.count { |g| g.send(stat) >= t } }
  end
end
