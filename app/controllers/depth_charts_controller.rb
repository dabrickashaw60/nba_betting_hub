require "set"

class DepthChartsController < ApplicationController
  SLOTS = ["G", "G", "F", "F", "C", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15"].freeze
  helper_method :build_depth_rows_for

  def index
    @season = Season.find_by(current: true)
    raise "No current season" unless @season

    @date =
      if params[:date].present?
        Date.parse(params[:date])
      else
        Date.current
      end

    @games = Game
      .where(date: @date, season_id: @season.id)
      .includes(:home_team, :visitor_team)
      .order(:id)

    team_ids = @games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq

    # Full roster (INCLUDES Out) for footer injury/status display
    all_roster_players = Player
      .where(team_id: team_ids)
      .includes(:health)
      .to_a

    @all_players_by_team = all_roster_players.group_by(&:team_id)

    # Active roster (EXCLUDES Out) for depth chart building
    active_roster_players = all_roster_players.reject { |p| p.health&.status.to_s == "Out" }
    @players_by_team = active_roster_players.group_by(&:team_id)

    # Projections for the date (expected minutes)
    @proj_minutes_by_team = Projection
      .where(date: @date, team_id: team_ids)
      .pluck(:team_id, :player_id, :expected_minutes)
      .each_with_object(Hash.new { |h, k| h[k] = {} }) do |(tid, pid, mins), h|
        h[tid][pid] = mins.to_f
      end

    # Season roles fallback ordering (if projections missing)
    roles = PlayerSeasonRole
      .where(season_id: @season.id)
      .joins(:player)
      .where(players: { team_id: team_ids })
      .includes(:player)
      .order(games_started: :desc, start_rate: :desc, games_played: :desc)
      .to_a

    @role_sorted_players_by_team =
      roles.group_by { |r| r.player.team_id }
          .transform_values { |arr| arr.map(&:player) }

    @role_by_team_player_id =
      roles.each_with_object(Hash.new { |h, k| h[k] = {} }) do |r, h|
        h[r.player.team_id][r.player_id] = r
      end
  end


  private

  def build_depth_rows_for(team_id)
    roster   = @players_by_team[team_id] || []
    proj_map = @proj_minutes_by_team[team_id] || {}
    role_map = @role_by_team_player_id[team_id] || {}

    # Sort roster by projection minutes if we have them; else by roles fallback
    players_sorted =
      if proj_map.any?
        roster.sort_by { |p| -proj_map.fetch(p.id, 0.0).to_f }
      else
        (@role_sorted_players_by_team[team_id] || roster)
      end

    starters = pick_starters(team_id, roster, proj_map, role_map, players_sorted)
    fill_depth_slots(players_sorted, proj_map, starters: starters)
  end


  def fill_depth_slots(players_sorted, proj_map, starters:)
    used = Set.new

    starters = starters.compact.first(5)
    starters.each { |p| used << p.id }

    # Assign starters into fixed slots with best-fit scoring
    starter_slots = ["G", "G", "F", "F", "C"]
    assignment = assign_players_to_slots(starters, starter_slots)

    # Order starters in slot order
    starters_in_slot_order = starter_slots.map.with_index do |slot, idx|
      assignment[[slot, idx]]
    end

    # Fill bench 6–15 by projected minutes (or fallback order)
    bench = players_sorted.reject { |p| used.include?(p.id) }.first(10)

    filled = (starters_in_slot_order + bench).first(15)

    SLOTS.each_with_index.map do |slot, idx|
      player = filled[idx]
      {
        slot: slot,
        player: player,
        pos: player&.position,
        expected_minutes: player ? proj_map.fetch(player.id, 0.0).to_f : nil
      }
    end
  end

  def pick_starters(team_id, roster, proj_map, role_map, players_sorted)
    # Prefer season starts, then minutes. This keeps “starter logic” stable.
    # If role data missing, fall back to minutes order.

    if role_map.any?
      ranked = roster.sort_by do |p|
        r = role_map[p.id]
        gs = r&.games_started.to_i
        sr = r&.start_rate.to_f
        gp = r&.games_played.to_i
        pm = proj_map.fetch(p.id, 0.0).to_f
        # Higher is better, so sort desc
        [-gs, -sr, -gp, -pm]
      end
      ranked.first(5)
    else
      players_sorted.first(5)
    end
  end

  def assign_players_to_slots(players, slots)
    # slots can include duplicates (two "G", two "F")
    # We'll brute-force all permutations of players into these slots and
    # pick the assignment with the best total score.
    return {} if players.blank?

    # For duplicate slots, distinguish by index to keep mapping stable
    indexed_slots = slots.map.with_index { |s, i| [s, i] }

    best_score = -Float::INFINITY
    best_map = {}

    players.permutation(players.size).each do |perm|
      score = 0.0
      map = {}

      indexed_slots.each_with_index do |(slot, idx), i|
        p = perm[i]
        map[[slot, idx]] = p
        score += slot_fit_score(p, slot)
      end

      if score > best_score
        best_score = score
        best_map = map
      end
    end

    best_map
  end

  def slot_fit_score(player, slot)
    # Higher = better fit. This is where we “correct” bad position labels.
    pos = player.position.to_s

    group =
      case pos
      when "PG", "SG" then "G"
      when "SF", "PF" then "F"
      when "C"        then "C"
      else "U"
      end

    case slot
    when "G"
      return 6.0 if group == "G"
      return 3.0 if group == "F" # wings can function as guards sometimes
      return 0.5 if group == "C"
      1.0
    when "F"
      return 6.0 if group == "F"
      return 2.5 if group == "G" # guard sliding up to wing
      return 2.0 if group == "C" # small-ball / big wing
      1.0
    when "C"
      return 6.0 if group == "C"
      return 2.0 if group == "F" # small-ball 5
      return 0.5 if group == "G"
      1.0
    else
      1.0
    end
  end

end