# lib/tasks/update_defense_data.rake
namespace :teams do
  desc "Update defense_vs_position for all teams"
  task update_defense_data: :environment do
    updated_count = 0
    skipped_count = 0

    puts "Starting update_defense_data task at #{Time.now}"

    Team.all.each_with_index do |team, index|
      begin
        puts "Processing Team ##{index + 1}: #{team.name} (ID: #{team.id})"

        defense_data = team.defense_vs_position
        parsed_data = JSON.parse(defense_data || "{}")
        serialized_data = parsed_data.deep_stringify_keys.to_json

        if team.defense_vs_position != serialized_data
          team.update!(defense_vs_position: serialized_data)
          updated_count += 1
          puts "Updated defense_vs_position for #{team.name}"
        else
          skipped_count += 1
          puts "No changes needed for #{team.name}"
        end
      rescue JSON::ParserError => e
        puts "Failed to parse defense_vs_position for #{team.name}: #{e.message}"
      rescue ActiveRecord::StatementInvalid => e
        puts "Database error for #{team.name}: #{e.message}"
      rescue => e
        puts "Unexpected error for #{team.name}: #{e.message}"
      end
    end

    puts "Task completed at #{Time.now}"
    puts "Total teams processed: #{Team.count}"
    puts "Total teams updated: #{updated_count}"
    puts "Total teams skipped: #{skipped_count}"
  end
end
