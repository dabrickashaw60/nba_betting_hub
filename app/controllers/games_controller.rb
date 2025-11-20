require "#{Rails.root}/app/services/scrapers/box_score_scraper"

class GamesController < ApplicationController
  before_action :set_current_season
  before_action :set_game, only: [:show, :scrape_box_score]

  def show
    @visitor_team = @game.visitor_team
    @home_team    = @game.home_team
    @visitor_standing = Standing.find_by(team_id: @game.visitor_team_id, season_id: @current_season.id)
    @home_standing    = Standing.find_by(team_id: @game.home_team_id, season_id: @current_season.id)
    @away_adv = TeamAdvancedStat.find_by(team: @visitor_team, season: @current_season)&.stats || {}
    @home_adv = TeamAdvancedStat.find_by(team: @home_team, season: @current_season)&.stats || {}
    @away_rank = TeamAdvancedStat.find_by(team: @visitor_team, season: @current_season)&.rankings || {}
    @home_rank = TeamAdvancedStat.find_by(team: @home_team, season: @current_season)&.rankings || {}

    # Filter by the current season for all data
    season_id = @current_season.id

    # Collect players from the two teams
    players = Player.where(team_id: [@visitor_team.id, @home_team.id]).includes(box_scores: :game)

    season_id = @current_season.id

    # Collect recent box scores for BOTH teams
    recent_box_scores = BoxScore.joins(:game)
                                .where(games: { season_id: season_id })
                                .where(player_id: players.ids)
                                .where.not(minutes_played: nil)
                                .order("games.date DESC")

    # Group by player_id
    grouped_by_player = recent_box_scores.group_by(&:player_id)

    # Build last 5 averages (same as home#index)
    all_player_data = players.map do |player|
      box_scores = grouped_by_player[player.id] || []
      last_five  = box_scores.first(5)
      last_ten   = box_scores.first(10)

      next if last_five.empty?

      avg5 = compute_bulk_averages(last_five)
      avg10 = compute_bulk_averages(last_ten)

      if avg5[:minutes_played] > 15
        { player: player, averages: avg5, last_ten_averages: avg10 }
      end
    end.compact

    # Split into away / home arrays for the two DataTables
    @away_preview_players = all_player_data.select { |x| x[:player].team_id == @visitor_team.id }
    @home_preview_players = all_player_data.select { |x| x[:player].team_id == @home_team.id }

    @previous_meetings = Game
      .where(season_id: @current_season.id)
      .where(
        "(visitor_team_id = ? AND home_team_id = ?) OR 
        (visitor_team_id = ? AND home_team_id = ?)",
        @visitor_team.id, @home_team.id,
        @home_team.id, @visitor_team.id
      )
      .where("date < ?", @game.date)
      .order(date: :desc)

    @away_dvp = @visitor_team.defense_data_for(@current_season) || {}
    @home_dvp = @home_team.defense_data_for(@current_season) || {}

    @positions = ["PG", "SG", "SF", "PF", "C"]

  end

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def set_current_season
    @current_season = Season.find_by(current: true)
  end

end
