class TeamsController < ApplicationController
  def index
    @teams = Team.includes(:players).order(:name) # This will load teams and their rosters
  end

  def show
    @team = Team.find(params[:id])
    @players = @team.players

    # Fetch last 5 games and next 5 games
    @last_five_games = @team.games.where("date < ?", Date.today).order(date: :desc).limit(5)
    @next_five_games = @team.games.where("date >= ?", Date.today).order(date: :asc).limit(5)
  end

end
