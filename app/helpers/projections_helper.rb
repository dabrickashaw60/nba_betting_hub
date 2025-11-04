module ProjectionsHelper
  # Compares projected value to last-5 average and returns a colored Bootstrap icon with tooltip
def trend_icon(projected, last5_avg)
  # --- Convert minutes like "31:45" to float if needed ---
  projected_val = parse_minutes_to_float(projected)
  last5_val     = parse_minutes_to_float(last5_avg)

  return "" if last5_val.to_f.zero?

  diff_pct = ((projected_val - last5_val) / last5_val) * 100.0

  case diff_pct
  when 20..Float::INFINITY
    icon  = "bi-arrow-up"
    color = "text-success"
    tip   = "Much higher than last 5 games"
  when 5..20
    icon  = "bi-arrow-up-short"
    color = "text-success"
    tip   = "Higher than last 5 games"
  when -Float::INFINITY..-20
    icon  = "bi-arrow-down"
    color = "text-danger"
    tip   = "Much lower than last 5 games"
  when -20..-5
    icon  = "bi-arrow-down-short"
    color = "text-danger"
    tip   = "Lower than last 5 games"
  else
    icon  = "bi-dash"
    color = "text-muted"
    tip   = "In line with last 5 games"
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
