module ProjectionsHelper
  # Compares projected value to last-5 average and returns a colored Bootstrap icon with tooltip
def trend_icon(projected, last5_avg)
  projected_val = parse_minutes_to_float(projected)
  last5_val     = parse_minutes_to_float(last5_avg)

  # No comparison if either is nil or zero
  return "" if projected_val.nil? || last5_val.nil? || last5_val.to_f.zero?

  diff_pct = ((projected_val - last5_val) / last5_val.to_f) * 100.0

  # Adjust sensitivity dynamically based on stat size
  sensitivity = if last5_val >= 20
                  1.0   # for large stats like points, rebounds
                elsif last5_val >= 10
                  1.25  # slightly more sensitive
                else
                  1.5   # smaller stats (assists, threes) — more sensitive
                end

  up_strong  = 20 / sensitivity
  up_light   = 5 / sensitivity
  down_light = -5 / sensitivity
  down_strong = -20 / sensitivity

  case diff_pct
  when up_strong..Float::INFINITY
    icon  = "bi-arrow-up"
    color = "text-success"
    tip   = "Much higher than last 5 games (#{diff_pct.round(1)}%)"
  when up_light...up_strong
    icon  = "bi-arrow-up-short"
    color = "text-success"
    tip   = "Slightly higher than last 5 games (#{diff_pct.round(1)}%)"
  when down_strong..down_light
    icon  = "bi-arrow-down-short"
    color = "text-danger"
    tip   = "Slightly lower than last 5 games (#{diff_pct.round(1)}%)"
  when -Float::INFINITY...down_strong
    icon  = "bi-arrow-down"
    color = "text-danger"
    tip   = "Much lower than last 5 games (#{diff_pct.round(1)}%)"
  else
    icon  = "bi-dash"
    color = "text-muted"
    tip   = "In line with last 5 games (#{diff_pct.round(1)}%)"
  end

  content_tag(
    :i, "",
    class: "bi #{icon} #{color} ms-1",
    data: { bs_toggle: "tooltip", bs_placement: "top" },
    title: tip
  )
end


private

def parse_minutes_to_float(value)
  return 0.0 if value.nil?
  return value.to_f if value.is_a?(Numeric)

  if value.is_a?(String) && value.include?(":")
    m, s = value.split(":").map(&:to_f)
    m + (s / 60.0)
  else
    value.to_f
  end
end


end
