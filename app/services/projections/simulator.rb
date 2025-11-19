module Projections
  class Simulator
    MODEL_VERSION = "simulation_dvp_v1".freeze
    RUNS = 1000  # Single deterministic projection since DvpOnlyModel already handles logic

    def initialize(date: Date.today)
      @date = date
      @season = Season.find_by(current: true)
      raise "No active season" unless @season

      # Use the new simplified model
      @model = Projections::DvpOnlyModel.new(date: @date)
    end

    def run!
      run = ProjectionRun.find_or_initialize_by(date: @date, model_version: MODEL_VERSION)
      return run if run.success?

      run.update!(status: :running, started_at: Time.current, projections_count: 0)

      todays_games = Game.where(date: @date, season_id: @season.id).includes(:home_team, :visitor_team)
      team_ids = todays_games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq
      return mark_success(run) if team_ids.blank?

      players = Player.where(team_id: team_ids).includes(:team)
      puts "=== Starting DvP Simulation for #{@date} (#{players.size} players, #{todays_games.size} games) ==="

      count = 0

      players.find_each.with_index(1) do |player, idx|
        begin
          opp = find_opponent(player, todays_games)
          next unless opp

          inputs = @model.send(:gather_inputs, player, opp)
          next if inputs.blank?

          outputs = @model.send(:project_stats, inputs)

          puts "[SIM #{idx}] #{player.name} (#{player.team.abbreviation}) vs #{opp.abbreviation} " \
               "→ P: #{outputs[:points].round(1)}, R: #{outputs[:rebounds].round(1)}, A: #{outputs[:assists].round(1)}"

          projection = Projection.find_or_initialize_by(date: @date, player_id: player.id)
          projection.assign_attributes(
            projection_run_id: run.id,
            team_id: player.team_id,
            opponent_team_id: opp.id,
            position: inputs[:position],
            proj_points: outputs[:points],
            proj_rebounds: outputs[:rebounds],
            proj_assists: outputs[:assists],
            proj_pa: outputs[:points] + outputs[:assists],
            proj_pr: outputs[:points] + outputs[:rebounds],
            proj_ra: outputs[:rebounds] + outputs[:assists],
            proj_pra: outputs[:points] + outputs[:rebounds] + outputs[:assists]
          )
          projection.save!
          count += 1
        rescue => e
          Rails.logger.warn "[Simulator] #{player.name} failed: #{e.message}"
          puts "    [ERROR] #{player.name}: #{e.message}"
          next
        end
      end

      run.update!(projections_count: count)
      mark_success(run)
    rescue => e
      run&.update!(status: :error, finished_at: Time.current, notes: e.message)
      raise
    end

    private

    def mark_success(run)
      run.update!(status: :success, finished_at: Time.current)
      puts "=== Simulation complete: #{run.projections_count} player projections saved ==="
      run
    end

    def find_opponent(player, todays_games)
      g = todays_games.detect { |game| game.home_team_id == player.team_id || game.visitor_team_id == player.team_id }
      return nil unless g
      g.home_team_id == player.team_id ? g.visitor_team : g.home_team
    end
  end
end
