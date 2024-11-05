# app/controllers/players_controller.rb
class PlayersController < ApplicationController

  def show
    @team = Team.find(params[:team_id])
    @player = @team.players.find(params[:id])
    @player_stats = @player.player_stats.order(season: :desc) # Assuming there's a `PlayerStat` model

        # Fetch all game logs for the player
    @game_logs = @player.box_scores.includes(:game).order('games.date DESC')

    # Fetch the last 5 game logs, most recent first
    @last_five_games = @game_logs.last(5)

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
end


