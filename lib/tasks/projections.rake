# lib/tasks/projections.rake
namespace :projections do
  desc "Build projections (DATE=YYYY-MM-DD, FORCE=1 to rebuild)"
  task build: :environment do
    date  = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.today
    force = ENV['FORCE'] == '1'

    if force
      ::ProjectionRun.where(date: date, model_version: "baseline_v1").delete_all
      puts "Forcing rebuild: removed existing ProjectionRun for #{date}"
    end

    puts "Building projections for #{date}…"
    Projections::BaselineModel.new(date: date).run!

    run = ::ProjectionRun.find_by(date: date, model_version: "baseline_v1")
    puts "Done: #{run&.status || 'unknown'} (#{run&.projections_count || 0} rows)"
  end
end
