namespace :projections do
  desc "Run Monte Carlo simulation for today's games"
  task simulate: :environment do
    date = Date.today
    run = Projections::Simulator.new(date: date).run!
    puts "Simulation complete for #{date}: #{run.projections_count} players projected (status: #{run.status})."
  end
end
