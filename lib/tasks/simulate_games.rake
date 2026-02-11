# lib/tasks/simulate_games.rake
namespace :sim do
  desc "Simulate games for a date (always rebuilds from projections)"
  task :date, [:date] => :environment do |_, args|
    date = args[:date].present? ? Date.parse(args[:date]) : Date.today

    model_version_single = Simulations::GameSimulator::MODEL_VERSION
    model_version_mc     = "#{Simulations::GameSimulator::MODEL_VERSION}_mc_v1"

    # Always wipe existing simulations for the date
    deleted = GameSimulation.where(
      date: date,
      model_version: [model_version_single, model_version_mc]
    ).delete_all

    puts "Deleted #{deleted} existing GameSimulation rows for #{date}"

    puts "Simulating games for #{date}..."
    sim = Simulations::GameSimulator.new(date: date)
    results = sim.simulate_date!(add_noise: false, persist: true)
    
    Game.where(date: date).find_each do |game|
      puts "Running Monte Carlo for Game #{game.id}..."

      mc = sim.simulate_game_distribution!(
        game_id: game.id,
        sims: 100,
        persist: true,
        debug: true,
        debug_samples: 25
      )

      puts "Spread Mean: #{mc[:outputs][:spread_mean].round(2)}"
      puts "Total Mean: #{mc[:outputs][:total_mean].round(2)}"
      puts "Spread SD: #{mc[:outputs][:spread_sd].round(2)}"
      puts "Total SD: #{mc[:outputs][:total_sd].round(2)}"

      if mc[:debug_samples].present?
        puts "First 5 debug samples:"
        mc[:debug_samples].first(5).each do |row|
          puts row
        end
      end

      puts "-----------------------------"
    end

    results.each do |r|
      game = Game.find(r[:game_id])
      home = game.home_team.abbreviation
      away = game.visitor_team.abbreviation
      puts "#{away} at #{home}: #{r[:visitor_totals][:points].round}-#{r[:home_totals][:points].round}"
    end

    puts "Done: simulated #{results.size} games."
  end
end
