namespace :pipeline do
  desc "Full refresh pipeline (injuries -> odds -> projections -> distributions -> game sims)"
  task refresh: :environment do
    date   = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.today
    season = Season.find_by(current: true)

    raise "No current season found" unless season

    puts "------------------------------------"
    puts "Starting pipeline refresh for #{date}"
    puts "------------------------------------"

    # ----------------------------------
    # 1. Injuries
    # ----------------------------------
    puts "Updating injuries..."
    Scrapers::InjuryScraper.scrape_and_update_injuries
    puts "Injuries updated"

    # ----------------------------------
    # 2. Odds
    # ----------------------------------
    puts "Importing odds..."
    odds_result = Odds::Importer.import_espn!(date: date)
    puts "Odds imported: #{odds_result.inspect}"

    # ----------------------------------
    # 3. Player projections
    # ----------------------------------
    puts "Rebuilding baseline projections..."

    Projection.where(date: date).delete_all
    ProjectionRun.where(
      date: date,
      model_version: Projections::BaselineModel::MODEL_VERSION
    ).delete_all

    run = Projections::BaselineModel.new(date: date).run!

    puts "Baseline projections rebuilt (#{run.projections_count})"

    # ----------------------------------
    # 4. Player distributions
    # ----------------------------------
    puts "Rebuilding player distributions..."

    player_mc_model = Projections::DistributionSimulator::MODEL_VERSION

    ProjectionDistribution.where(
      date: date,
      model_version: player_mc_model
    ).delete_all

    dist_count =
      Projections::DistributionSimulator
        .new(date: date, sims: 500, model_version: player_mc_model, force: true)
        .run!

    puts "Player distributions rebuilt (#{dist_count})"

    # ----------------------------------
    # 5. Game simulations
    # ----------------------------------
    puts "Rebuilding game simulations..."

    sim_model_means = Simulations::GameFromPlayerMeans::MODEL_VERSION

    GameSimulation.where(
      date: date,
      model_version: sim_model_means
    ).delete_all

    builder = Simulations::GameFromPlayerMeans.new(
      date: date,
      season: season,
      player_model_version: player_mc_model
    )

    games = Game.where(date: date, season_id: season.id)

    games.find_each do |game|
      builder.build!(game_id: game.id, persist: true)
    end

    puts "Game simulations built for #{games.count} games"

    puts "------------------------------------"
    puts "Pipeline refresh complete"
    puts "------------------------------------"
  end
end