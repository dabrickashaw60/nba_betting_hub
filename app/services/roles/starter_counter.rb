module Roles
  class StarterCounter
    def initialize(season:)
      @season = season
    end

    def run!
      game_ids = Game.where(season_id: @season.id).pluck(:id)
      return if game_ids.blank?

      # Pull all box scores with minutes for season games
      rows = BoxScore
        .where(game_id: game_ids)
        .where.not(minutes_played: [nil, "", "0:00"])
        .pluck(:game_id, :team_id, :player_id, :minutes_played)

      return if rows.blank?

      played  = Hash.new(0) # player_id -> games played count
      started = Hash.new(0) # player_id -> games started count

      # Group by game + team, then choose top 5 by minutes
      rows.group_by { |gid, tid, _pid, _mp| [gid, tid] }.each do |_key, group|
        group.each { |_gid, _tid, pid, _mp| played[pid] += 1 }

        top5 = group
          .sort_by { |_gid, _tid, _pid, mp| -minutes_to_float(mp) }
          .first(5)

        top5.each { |_gid, _tid, pid, _mp| started[pid] += 1 }
      end

      rebuild_roles!(played, started)

    end

    private

    def minutes_to_float(value)
      return 0.0 if value.blank?
      return value.to_f if value.is_a?(Numeric)
      return value.to_f unless value.include?(":")

      m, s = value.split(":").map(&:to_i)
      m + (s / 60.0)
    rescue
      0.0
    end

    def rebuild_roles!(played, started)
      player_ids = played.keys
      return if player_ids.blank?

      now = Time.current

      # snapshot team/position at build time
      player_info = Player.where(id: player_ids).pluck(:id, :team_id, :position).to_h do |id, team_id, pos|
        [id, { team_id: team_id, position: pos }]
      end

      payload = player_ids.map do |pid|
        gp = played[pid].to_i
        gs = started[pid].to_i
        bg = [gp - gs, 0].max
        sr = gp > 0 ? (gs.to_f / gp.to_f) : 0.0

        info = player_info[pid] || {}

        {
          season_id: @season.id,
          player_id: pid,
          team_id: info[:team_id],
          position: info[:position],
          games_played: gp,
          games_started: gs,
          bench_games: bg,
          start_rate: sr,
          created_at: now,
          updated_at: now
        }
      end

      PlayerSeasonRole.transaction do
        PlayerSeasonRole.where(season_id: @season.id).delete_all
        PlayerSeasonRole.insert_all(payload) if payload.any?
      end
    end

  end
end
