class TeamsController < ApplicationController
  def index
    @teams = Team.includes(:players).order(:name) # This will load teams and their rosters
  end

  def show
    @team = Team.find(params[:id])
    @players = @team.players.includes(:player_stat) # Load players with their stats
    @player_stats = @players.map(&:player_stat).compact # Get player stats, excluding nils for players without stats

    # Load the team's full schedule
    @team_schedule = @team.games.order(:date) # Ensure the games are ordered by date
  end

end
