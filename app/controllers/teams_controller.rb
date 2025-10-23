class TeamsController < ApplicationController
  before_action :set_current_season

  # ---------------------------------------------------------------------------
  # 🏀 INDEX: show all teams with rosters
  # ---------------------------------------------------------------------------
  def index
    @teams = Team.includes(:players).order(:name)
  end

  # ---------------------------------------------------------------------------
  # 🧾 SHOW: team detail page (roster, stats, schedule)
  # ---------------------------------------------------------------------------
  def show
    @team = Team.find(params[:id])

    # Load players and their stats for current season
    @players = @team.players.includes(:player_stats)
    @player_stats = @players.map do |player|
      player.player_stats.find_by(season_id: @current_season.id)
    end.compact

    # Team schedule for the current season
    @team_schedule = @team.games.where(season_id: @current_season.id)
                                .order(:date)
                                .includes(:home_team, :visitor_team)
  end

  # ---------------------------------------------------------------------------
  # 🧱 DEFENSE VS POSITION VIEW
  # ---------------------------------------------------------------------------
  def defense_vs_position
    @position = params[:position] || "PG"
    @seasons = Season.order(start_date: :desc)
    @selected_season =
      if params[:season_id].present?
        Season.find_by(id: params[:season_id])
      else
        Season.find_by(current: true) || @seasons.first
      end

    if @selected_season.nil?
      flash[:alert] = "No season found."
      redirect_to root_path and return
    end

    @teams = Team.includes(:defense_vs_positions).map do |team|
      defense_data = team.defense_data_for(@selected_season) || {}
      team.define_singleton_method(:parsed_defense_vs_position) { defense_data }
      team
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end



  # ---------------------------------------------------------------------------
  # 🔧 PRIVATE METHODS
  # ---------------------------------------------------------------------------
  private

  def set_current_season
    @current_season = Season.find_by(current: true)
  end

  # Ensure all team defense data is valid JSON
  def update_team_defense_data
    Team.find_each do |team|
      begin
        parsed_data = JSON.parse(team.defense_vs_position || "{}")
        serialized_data = parsed_data.deep_stringify_keys.to_json
        team.update!(defense_vs_position: serialized_data)
        Rails.logger.info "Updated defense_vs_position for #{team.name}"
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse defense_vs_position for #{team.name}: #{e.message}"
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.error "Database error for #{team.name}: #{e.message}"
      end
    end
  end
end
