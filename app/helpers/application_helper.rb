module ApplicationHelper
  def rank_color_class(rank)
    case rank
    when 1..10
      'bg-danger text-white'   # Red for bad matchup
    when 11..20
      'bg-warning text-dark'   # Yellow for okay matchup
    when 21..30
      'bg-success text-white'  # Green for good matchup
    else
      ''                       # No color if rank is not within the range
    end
  end
end
