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
    Rails.logger.debug("Entering defense_vs_position action")

    # Ensure team defense data is serialized correctly
    update_team_defense_data

    # Parse defense JSON for each team
    @teams = Team.all.map do |team|
      parsed_data = JSON.parse(team.defense_vs_position || "{}") rescue {}
      team.define_singleton_method(:parsed_defense_vs_position) { parsed_data }
      team
    end

    @position = params[:position] || "PG"

    respond_to do |format|
      format.html
      format.turbo_stream do
        Rails.logger.debug("Rendering turbo stream with position: #{@position}")
        render turbo_stream: turbo_stream.replace(
          "defense_table",
          partial: "teams/defense_table",
          locals: { teams: @teams, position: @position }
        )
      end
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
