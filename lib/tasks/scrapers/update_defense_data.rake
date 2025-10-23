# lib/tasks/update_defense_data.rake
namespace :teams do
  desc "Rebuild Defense vs Position data for all teams by season"
  task update_defense_data: :environment do
    puts "Starting DefenseVsPosition rebuild at #{Time.now}"

    # Use the current season, or fall back to the most recent one
    current_season = Season.find_by(current: true) || Season.order(:start_date).last

    if current_season.nil?
      puts "❌ No active or recent season found. Aborting task."
      exit
    end

    puts "Processing season: #{current_season.name} (ID: #{current_season.id})"

    begin
      DefenseVsPosition.rebuild_all_for_season(current_season)
      puts "✅ Successfully rebuilt DefenseVsPosition for #{current_season.name}"
    rescue => e
      puts "❌ Error rebuilding DefenseVsPosition: #{e.message}"
      puts e.backtrace.take(10)
    end

    puts "Task completed at #{Time.now}"
  end
end
