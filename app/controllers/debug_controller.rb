class DebugController < ApplicationController
  def team_stats
    team = Team.find(params[:team_id])
    season = Season.find_by(current: true)
    record = TeamAdvancedStat.find_by(team: team, season: season)

    if record.nil?
      render plain: "No record found for team #{team.name}", status: 404
    else
      render json: {
        team: team.name,
        stats: record.stats,
        rankings: record.rankings
      }
    end
  end
end
