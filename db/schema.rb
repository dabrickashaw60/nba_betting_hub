# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2025_10_30_193325) do

  create_table "box_scores", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "team_id", null: false
    t.bigint "player_id", null: false
    t.string "minutes_played"
    t.integer "field_goals"
    t.integer "field_goals_attempted"
    t.float "field_goal_percentage"
    t.integer "three_point_field_goals"
    t.integer "three_point_field_goals_attempted"
    t.float "three_point_percentage"
    t.integer "free_throws"
    t.integer "free_throws_attempted"
    t.float "free_throw_percentage"
    t.integer "offensive_rebounds"
    t.integer "defensive_rebounds"
    t.integer "total_rebounds"
    t.integer "assists"
    t.integer "steals"
    t.integer "blocks"
    t.integer "turnovers"
    t.integer "personal_fouls"
    t.integer "points"
    t.float "game_score"
    t.float "plus_minus"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "season_id"
    t.float "true_shooting_pct"
    t.float "effective_fg_pct"
    t.float "three_point_attempt_rate"
    t.float "free_throw_rate"
    t.float "offensive_rebound_pct"
    t.float "defensive_rebound_pct"
    t.float "total_rebound_pct"
    t.float "assist_pct"
    t.float "steal_pct"
    t.float "block_pct"
    t.float "turnover_pct"
    t.float "usage_pct"
    t.integer "offensive_rating"
    t.integer "defensive_rating"
    t.float "box_plus_minus"
    t.index ["game_id"], name: "index_box_scores_on_game_id"
    t.index ["player_id"], name: "index_box_scores_on_player_id"
    t.index ["team_id"], name: "index_box_scores_on_team_id"
  end

  create_table "defense_vs_positions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.text "data", size: :long, collation: "utf8mb4_bin"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["season_id"], name: "index_defense_vs_positions_on_season_id"
    t.index ["team_id"], name: "index_defense_vs_positions_on_team_id"
    t.check_constraint "json_valid(`data`)", name: "data"
  end

  create_table "games", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.date "date"
    t.time "time"
    t.bigint "home_team_id", null: false
    t.string "location"
    t.integer "week"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.time "start_time"
    t.integer "attendance"
    t.string "duration"
    t.string "notes"
    t.bigint "visitor_team_id", null: false
    t.integer "visitor_points"
    t.integer "home_points"
    t.string "game_duration"
    t.boolean "overtime"
    t.integer "season_id"
    t.string "game_type"
    t.index ["home_team_id"], name: "index_games_on_home_team_id"
    t.index ["visitor_team_id"], name: "index_games_on_visitor_team_id"
  end

  create_table "healths", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.string "status"
    t.text "description"
    t.date "last_update"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["player_id"], name: "index_healths_on_player_id"
  end

  create_table "player_stats", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "player_id"
    t.integer "games_played"
    t.string "minutes_played"
    t.float "field_goals"
    t.float "field_goals_attempted"
    t.float "field_goal_percentage"
    t.float "three_point_field_goals"
    t.float "three_point_field_goals_attempted"
    t.float "three_point_percentage"
    t.float "free_throws"
    t.float "free_throws_attempted"
    t.float "free_throw_percentage"
    t.float "offensive_rebounds"
    t.float "defensive_rebounds"
    t.float "total_rebounds"
    t.float "assists"
    t.float "steals"
    t.float "blocks"
    t.float "turnovers"
    t.float "personal_fouls"
    t.float "points"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.float "game_score"
    t.float "plus_minus"
    t.integer "season_id"
    t.float "true_shooting_pct"
    t.float "effective_fg_pct"
    t.float "three_point_attempt_rate"
    t.float "free_throw_rate"
    t.float "offensive_rebound_pct"
    t.float "defensive_rebound_pct"
    t.float "total_rebound_pct"
    t.float "assist_pct"
    t.float "steal_pct"
    t.float "block_pct"
    t.float "turnover_pct"
    t.float "usage_pct"
    t.float "offensive_rating"
    t.float "defensive_rating"
    t.float "box_plus_minus"
    t.index ["player_id"], name: "index_player_stats_on_player_id"
  end

  create_table "players", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "from_year", null: false
    t.integer "to_year", null: false
    t.string "position", null: false
    t.string "height", null: false
    t.integer "weight", null: false
    t.date "birth_date", null: false
    t.string "college"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "team_id"
    t.integer "uniform_number"
    t.string "country_of_birth"
    t.index ["team_id"], name: "index_players_on_team_id"
  end

  create_table "seasons", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.string "season_type"
    t.boolean "current", default: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "standings", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "team_id"
    t.integer "season"
    t.integer "wins"
    t.integer "losses"
    t.float "win_percentage"
    t.string "games_behind"
    t.float "points_per_game"
    t.float "opponent_points_per_game"
    t.float "srs"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "conference"
    t.integer "season_id"
    t.index ["team_id"], name: "index_standings_on_team_id"
  end

  create_table "teams", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "abbreviation"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "defense_vs_position", size: :long, collation: "utf8mb4_bin"
    t.check_constraint "json_valid(`defense_vs_position`)", name: "defense_vs_position"
  end

  add_foreign_key "box_scores", "games"
  add_foreign_key "box_scores", "players"
  add_foreign_key "box_scores", "teams"
  add_foreign_key "defense_vs_positions", "seasons"
  add_foreign_key "defense_vs_positions", "teams"
  add_foreign_key "games", "teams", column: "home_team_id"
  add_foreign_key "healths", "players"
  add_foreign_key "player_stats", "players"
  add_foreign_key "players", "teams"
  add_foreign_key "standings", "teams"
end
