class PlayerStat < ApplicationRecord
  belongs_to :player
  validates :season, presence: true

  # Update averages for the 2024-2025 season only
  SEASON = "2024-2025".freeze

  def self.update_season_averages(player)
    box_scores = player.box_scores
    return if box_scores.empty?

    # Find or initialize a single PlayerStat record for the player and 2024-2025 season
    player_stat = PlayerStat.find_or_initialize_by(player: player, season: SEASON)

    player_stat.games_played = box_scores.count
    player_stat.field_goals = box_scores.average(:field_goals)
    player_stat.field_goals_attempted = box_scores.average(:field_goals_attempted)
    player_stat.field_goal_percentage = player_stat.field_goals_attempted > 0 ? (player_stat.field_goals / player_stat.field_goals_attempted.to_f) : 0
    
    player_stat.three_point_field_goals = box_scores.average(:three_point_field_goals)
    player_stat.three_point_field_goals_attempted = box_scores.average(:three_point_field_goals_attempted)
    player_stat.three_point_percentage = player_stat.three_point_field_goals_attempted > 0 ? (player_stat.three_point_field_goals / player_stat.three_point_field_goals_attempted.to_f) : 0
    
    player_stat.free_throws = box_scores.average(:free_throws)
    player_stat.free_throws_attempted = box_scores.average(:free_throws_attempted)
    player_stat.free_throw_percentage = player_stat.free_throws_attempted > 0 ? (player_stat.free_throws / player_stat.free_throws_attempted.to_f) : 0
    
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
    
    # Calculate average minutes per game
    total_seconds = box_scores.sum { |bs| convert_to_seconds(bs.minutes_played) }
    average_seconds = total_seconds / box_scores.count
    player_stat.minutes_played = format_seconds_as_time(average_seconds)

    # Save or update the PlayerStat record for the 2024-2025 season
    player_stat.save!
  end

  # Helper method to convert "MM:SS" to total seconds
  def self.convert_to_seconds(time_str)
    return 0 if time_str.nil?
    minutes, seconds = time_str.split(":").map(&:to_i)
    (minutes * 60) + seconds
  end

  # Helper method to convert seconds back to "MM:SS" format
  def self.format_seconds_as_time(total_seconds)
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    format("%02d:%02d", minutes, seconds)
  end

  before_save :round_stats_to_one_decimal

  private

  def round_stats_to_one_decimal
    # List of attributes to round to 1 decimal place, excluding minutes_played
    [:field_goals, :field_goals_attempted, :field_goal_percentage,
     :three_point_field_goals, :three_point_field_goals_attempted, :three_point_percentage,
     :free_throws, :free_throws_attempted, :free_throw_percentage,
     :offensive_rebounds, :defensive_rebounds, :total_rebounds,
     :assists, :steals, :blocks, :turnovers, :personal_fouls,
     :points, :game_score, :plus_minus].each do |attribute|
      # Round each attribute to 1 decimal place if it's not nil
      self[attribute] = self[attribute]&.round(3)
    end
  end
end
