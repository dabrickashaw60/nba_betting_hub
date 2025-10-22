# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
# db/seeds.rb

Season.create!(
  name: "2024-2025",
  start_date: "2024-10-20",
  end_date: "2025-06-30",
  season_type: "Regular",
  current: true
)

Season.create!(
  name: "2025-2026",
  start_date: "2025-10-20",
  end_date: "2026-06-30",
  season_type: "Regular",
  current: false
)
