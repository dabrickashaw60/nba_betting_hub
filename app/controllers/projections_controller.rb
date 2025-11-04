# app/controllers/projections_controller.rb
class ProjectionsController < ApplicationController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @run  = ProjectionRun.find_by(date: @date, model_version: Projections::BaselineModel::MODEL_VERSION)
    season_id = Season.find_by(current: true)&.id

    @projections = Projection.includes(:player, :team)
                            .where(date: @date)
                            .map do |proj|
    last5 = proj.player.box_scores
              .joins(:game)
              .where(games: { season_id: season_id })
              .where.not(minutes_played: [nil, ""])
              .order("games.date DESC")
              .limit(5)

    # --- Helper method to calculate average minutes (copied from PlayersController) ---
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

    # --- Usage % average ---
    usage_values = last5.pluck(:usage_pct).compact.map(&:to_f)
    avg_usage = usage_values.any? ? (usage_values.sum / usage_values.size).round(1) : 0.0

    # --- Build last5 averages hash ---
    last5_avg = {
      points:          last5.average(:points).to_f.round(1),
      rebounds:        last5.average(:total_rebounds).to_f.round(1),
      assists:         last5.average(:assists).to_f.round(1),
      usage_pct:       avg_usage,
      minutes_played:  calculate_average_minutes(last5)
    }

      {
        projection: proj,
        last5_avg: last5_avg
      }
    end
  end
  

  def show
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @projection = Projection.includes(:player, :team, :opponent_team)
                            .find_by!(date: @date, player_id: params[:id])
  end

  def generate
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    run = Projections::Simulator.new(date: date).run!
    redirect_to projections_path(date: date), notice: "Simulation completed with #{run.projections_count} players."
  end

end

