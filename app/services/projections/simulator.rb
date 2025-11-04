module Projections
  class Simulator
    RUNS = 1000
    MODEL_VERSION = "simulation_v1".freeze

    def initialize(date: Date.today)
      @date = date
      @season = Season.find_by(current: true)
      raise "No active season" unless @season
      @model = Projections::BaselineModel.new(date: @date)
    end

    def run!
      run = ProjectionRun.find_or_initialize_by(date: @date, model_version: MODEL_VERSION)
      return run if run.success?

      run.update!(status: :running, started_at: Time.current, projections_count: 0)

      todays_games = Game.where(date: @date, season_id: @season.id)
                         .includes(:home_team, :visitor_team)

      team_ids = todays_games.flat_map { |g| [g.home_team_id, g.visitor_team_id] }.uniq
      players = Player.where(team_id: team_ids).includes(:team)
      return mark_success(run) if players.blank?

      puts "=== Starting Simulation for #{@date} (#{players.size} players across #{todays_games.size} games) ==="
      count = 0

      players.find_each.with_index(1) do |player, idx|
        begin
          opp = find_opponent(player, todays_games)
          next unless opp

          inputs = @model.send(:gather_inputs, player, opp)
          next unless inputs

          puts "[SIM #{idx}] #{player.name} (#{player.team.abbreviation}) vs #{opp.abbreviation}"

          # Run Monte Carlo simulations
          sims = RUNS.times.map { @model.send(:project_stats, inputs) }

          avg = average_sims(sims)

          # Log averages for debug
          puts "    → avg_pts=#{avg[:points].round(1)}  reb=#{avg[:rebounds].round(1)}  ast=#{avg[:assists].round(1)}  "\
               "ast%=#{avg[:assist_pct].round(1)}  reb%=#{avg[:rebound_pct].round(1)}"

          projection = Projection.find_or_initialize_by(date: @date, player_id: player.id)
          projection.assign_attributes(
            projection_run_id: run.id,
            team_id: player.team_id,
            opponent_team_id: opp.id,
            position: inputs[:position],
            injury_status: inputs[:injury_status],
            expected_minutes: inputs[:expected_minutes],
            usage_pct: inputs[:usage_pct],
            dvp_pts_mult: inputs[:dvp_pts_mult],
            dvp_reb_mult: inputs[:dvp_reb_mult],
            dvp_ast_mult: inputs[:dvp_ast_mult],

            proj_points: avg[:points],
            proj_rebounds: avg[:rebounds],
            proj_assists: avg[:assists],
            proj_threes: avg[:threes],
            proj_steals: avg[:steals],
            proj_blocks: avg[:blocks],
            proj_turnovers: avg[:turnovers],
            proj_plus_minus: avg[:plus_minus],

            assist_pct: avg[:assist_pct],
            rebound_pct: avg[:rebound_pct],

            proj_pa: avg[:points] + avg[:assists],
            proj_pr: avg[:points] + avg[:rebounds],
            proj_ra: avg[:rebounds] + avg[:assists],
            proj_pra: avg[:points] + avg[:rebounds] + avg[:assists]
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

    def average_sims(sims)
      stat_keys = sims.first.keys
      avg = {}
      stat_keys.each do |key|
        values = sims.map { |h| h[key].to_f }
        avg[key] = (values.sum / values.size.to_f).round(2)
      end
      avg
    end
  end
end
