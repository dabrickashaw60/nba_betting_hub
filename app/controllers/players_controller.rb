# app/controllers/players_controller.rb
class PlayersController < ApplicationController

  def show
    @team = Team.find(params[:team_id])
    @player = @team.players.find(params[:id])
    @player_stats = @player.player_stats.order(season: :desc) # Assuming there's a `PlayerStat` model
    
    # Fetch all game logs for the player
    @game_logs = @player.box_scores.includes(:game).order('games.date DESC')
    
    # Fetch the last 5 game logs, most recent first
    @last_five_games = @game_logs.limit(5)
  
    # Calculate averages for the last 5 games
    @last_five_averages = {
      minutes_played: calculate_average_minutes(@last_five_games),
      points: average_stat(@last_five_games, :points),
      rebounds: average_stat(@last_five_games, :total_rebounds),
      assists: average_stat(@last_five_games, :assists),
      field_goals: average_ratio(@last_five_games, :field_goals, :field_goals_attempted),
      three_pointers: average_ratio(@last_five_games, :three_point_field_goals, :three_point_field_goals_attempted),
      free_throws: average_ratio(@last_five_games, :free_throws, :free_throws_attempted),
      plus_minus: average_stat(@last_five_games, :plus_minus),
      steals: average_stat(@last_five_games, :steals),
      blocks: average_stat(@last_five_games, :blocks),
      turnovers: average_stat(@last_five_games, :turnovers),
      personal_fouls: average_stat(@last_five_games, :personal_fouls)      
    }

      # Betting info calculation
      @betting_info = {
        points: count_thresholds(@last_five_games, :points, [10, 15, 20, 25, 30]),
        threes: count_thresholds(@last_five_games, :three_point_field_goals, [1, 2, 3, 4, 5]),
        rebounds: count_thresholds(@last_five_games, :total_rebounds, [2, 4, 6, 8, 10]),
        assists: count_thresholds(@last_five_games, :assists, [2, 4, 6, 8, 10])
      }
  end

  def update_stats
    @player = Player.find_by(id: params[:id])
    @team = Team.find_by(id: params[:team_id])

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

    # Redirect to the player's show page after updating stats
    redirect_to team_path(@team, anchor: 'player-stats')

  end

  private

  def average_stat(games, stat)
    games.sum(&stat).to_f / games.size
  end

  # Helper method to calculate the average minutes in "MM:SS" format
  def calculate_average_minutes(games)
    total_seconds = games.sum { |game| game.minutes_played.split(":").first.to_i * 60 + game.minutes_played.split(":").last.to_i }
    average_seconds = total_seconds / games.size
    minutes = average_seconds / 60
    seconds = average_seconds % 60
    format("%02d:%02d", minutes, seconds)
  end

  # Helper method to calculate field goal, three-point, and free throw averages in "makes / attempts" format
  def average_ratio(games, made_stat, attempted_stat)
    total_made = games.sum(&made_stat)
    total_attempted = games.sum(&attempted_stat)
    if total_attempted > 0
      "#{(total_made.to_f / games.size).round(1)} / #{(total_attempted.to_f / games.size).round(1)}"
    else
      "0.0 / 0.0"
    end
  end

  def count_thresholds(games, stat, thresholds)
    thresholds.map do |threshold|
      games.count { |game| game.send(stat) >= threshold }
    end
  end

end


