class PlayerStat < ApplicationRecord
  belongs_to :player
  belongs_to :season

  # Scope for current season
  scope :current, -> { where(season_id: Season.find_by(current: true)&.id) }

  # Ensure both player and season are present
  validates :player, presence: true
  validates :season, presence: true

  # Update averages for the current season only
  def self.update_season_averages(player)
    current_season = Season.find_by(current: true)
    return unless current_season

    # Only include box scores from the current season
    box_scores = player.box_scores.where(season_id: current_season.id)
    return if box_scores.empty?

    # Find or initialize the player's season stat record
    player_stat = PlayerStat.find_or_initialize_by(player: player, season: current_season)

    player_stat.games_played = box_scores.count
    player_stat.field_goals = box_scores.average(:field_goals)
    player_stat.field_goals_attempted = box_scores.average(:field_goals_attempted)
    player_stat.field_goal_percentage =
      if player_stat.field_goals_attempted.to_f > 0
        player_stat.field_goals / player_stat.field_goals_attempted.to_f
      else
        0
      end

    player_stat.three_point_field_goals = box_scores.average(:three_point_field_goals)
    player_stat.three_point_field_goals_attempted = box_scores.average(:three_point_field_goals_attempted)
    player_stat.three_point_percentage =
      if player_stat.three_point_field_goals_attempted.to_f > 0
        player_stat.three_point_field_goals / player_stat.three_point_field_goals_attempted.to_f
      else
        0
      end

    player_stat.free_throws = box_scores.average(:free_throws)
    player_stat.free_throws_attempted = box_scores.average(:free_throws_attempted)
    player_stat.free_throw_percentage =
      if player_stat.free_throws_attempted.to_f > 0
        player_stat.free_throws / player_stat.free_throws_attempted.to_f
      else
        0
      end

    player_stat.offensive_rebounds = box_scores.average(:offensive_rebounds)
    player_stat.defensive_rebounds = box_scores.average(:defensive_rebounds)
    player_stat.total_rebounds = box_scores.average(:total_rebounds)
    player_stat.assists = box_scores.average(:assists)
    player_stat.steals = box_scores.average(:steals)
    player_stat.blocks = box_scores.average(:blocks)
    player_stat.turnovers = box_scores.average(:turnovers)
    player_stat.personal_fouls = box_scores.average(:personal_fouls)
    player_stat.points = box_scores.average(:points)
    player_stat.game_score = box_scores.average(:game_score)
    player_stat.plus_minus = box_scores.average(:plus_minus)

    # Calculate average minutes played (MM:SS)
    valid_box_scores = box_scores.where.not(minutes_played: [nil, ""])
    if valid_box_scores.empty?
      player_stat.minutes_played = "00:00"
    else
      total_seconds = valid_box_scores.sum { |bs| convert_to_seconds(bs.minutes_played) }
      average_seconds = total_seconds / valid_box_scores.size
      player_stat.minutes_played = format_seconds_as_time(average_seconds)
    end

    Rails.logger.debug "Saving PlayerStat for #{player.name} (#{current_season.name}): #{player_stat.minutes_played}"
    player_stat.save!
  end

  # Convert "MM:SS" to seconds
  def self.convert_to_seconds(time_str)
    return 0 if time_str.blank?
    minutes, seconds = time_str.split(":").map(&:to_i)
    (minutes * 60) + seconds
  end

  # Convert seconds to "MM:SS"
  def self.format_seconds_as_time(total_seconds)
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    format("%02d:%02d", minutes, seconds)
  end

  before_save :round_stats_to_three_decimals

  private

  def round_stats_to_three_decimals
    [
      :field_goals, :field_goals_attempted, :field_goal_percentage,
      :three_point_field_goals, :three_point_field_goals_attempted, :three_point_percentage,
      :free_throws, :free_throws_attempted, :free_throw_percentage,
      :offensive_rebounds, :defensive_rebounds, :total_rebounds,
      :assists, :steals, :blocks, :turnovers, :personal_fouls,
      :points, :game_score, :plus_minus
    ].each do |attr|
      self[attr] = self[attr]&.round(3)
    end
  end
end
