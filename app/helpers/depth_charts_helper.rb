module DepthChartsHelper
  def depth_game_time(game)
    # adjust these fields based on your schema
    if game.respond_to?(:start_time) && game.start_time.present?
      game.start_time.in_time_zone("Eastern Time (US & Canada)").strftime("%-I:%M %p ET")
    elsif game.respond_to?(:game_time) && game.game_time.present?
      game.game_time.to_s
    else
      "Time TBD"
    end
  rescue
    "Time TBD"
  end
end
