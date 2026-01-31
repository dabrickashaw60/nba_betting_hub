module ApplicationHelper
    def rank_color_class(rank)
      return '' if rank.nil? || rank < 1 || rank > 30
    
      # Define the RGB color stops
      red   = [162, 0, 0]         # Rank 1
      white = [255, 255, 255]     # Rank 15
      green = [76, 175, 80]       # Rank 30
    
      # Interpolate red → white for ranks 1–15
      if rank <= 15
        ratio = (rank - 1).to_f / 14
        r = (red[0] + (white[0] - red[0]) * ratio).round
        g = (red[1] + (white[1] - red[1]) * ratio).round
        b = (red[2] + (white[2] - red[2]) * ratio).round
      else
        # Interpolate white → green for ranks 16–30
        ratio = (rank - 16).to_f / 14
        r = (white[0] + (green[0] - white[0]) * ratio).round
        g = (white[1] + (green[1] - white[1]) * ratio).round
        b = (white[2] + (green[2] - white[2]) * ratio).round
      end
    
      # Choose text color for contrast
      luminance = 0.299 * r + 0.587 * g + 0.114 * b
    
      "background-color: rgb(#{r}, #{g}, #{b}); color: black;"
    end
    def reverse_rank_color_class(rank)
      return '' if rank.nil? || rank < 1 || rank > 30

      # Flip the rank: 1 ↔ 30, 2 ↔ 29, etc.
      reversed_rank = 31 - rank

      # Reuse the same gradient logic by calling the original helper
      rank_color_class(reversed_rank)
    end


  
  def health_status(status)
    case status
    when "Out"
      " (O)"
    when "Day-To-Day"
      " (DTD)"
    else
      ""
    end
  end
end
