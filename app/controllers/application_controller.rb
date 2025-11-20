class ApplicationController < ActionController::Base

  private

    def compute_bulk_averages(box_scores)
      count = box_scores.size.to_f
      {
        minutes_played: minutes_as_float(box_scores),
        minutes_display: avg_minutes(box_scores),
        points: box_scores.sum(&:points).to_f / count,
        rebounds: box_scores.sum(&:total_rebounds).to_f / count,
        assists: box_scores.sum(&:assists).to_f / count,
        three_point_field_goals: box_scores.sum(&:three_point_field_goals).to_f / count,
        usage_pct: box_scores.sum { |b| b.usage_pct.to_f } / count,
        trb_pct:   box_scores.sum { |b| b.total_rebound_pct.to_f } / count,
        ast_pct:   box_scores.sum { |b| b.assist_pct.to_f } / count,
        minutes_display: format_minutes_for_display(box_scores)
      }
    end

    def avg_minutes(box_scores)
      valid_games = box_scores.select { |g| g.minutes_played.present? }
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

    def format_minutes_for_display(box_scores)
      avg_minutes(box_scores)
    end

    def minutes_as_float(box_scores)
      valid = box_scores.select { |g| g.minutes_played.present? }
      return 0 if valid.empty?

      total_sec = valid.sum do |g|
        m, s = g.minutes_played.split(":").map(&:to_i)
        (m * 60) + s
      end

      total_sec / 60.0 / valid.size
    end


end
