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

ActiveRecord::Schema.define(version: 2026_02_09_000000) do

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
    t.check_constraint "son_valid(`data`", name: "defense_vs_positions_chk_1"
  end

  create_table "game_simulations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "date", null: false
    t.bigint "game_id", null: false
    t.bigint "season_id", null: false
    t.bigint "home_team_id", null: false
    t.bigint "visitor_team_id", null: false
    t.string "model_version", null: false
    t.integer "sims_count", default: 1, null: false
    t.integer "home_points", default: 0, null: false
    t.integer "visitor_points", default: 0, null: false
    t.decimal "home_rebounds", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_rebounds", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_assists", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_assists", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_threes", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_threes", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_baseline_points", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_baseline_points", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_baseline_rebounds", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_baseline_rebounds", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_baseline_assists", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_baseline_assists", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_baseline_threes", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "visitor_baseline_threes", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "home_scale", precision: 8, scale: 4, default: "1.0", null: false
    t.decimal "visitor_scale", precision: 8, scale: 4, default: "1.0", null: false
    t.json "meta"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date", "game_id", "model_version"], name: "index_game_simulations_on_date_and_game_id_and_model_version", unique: true
    t.index ["date"], name: "index_game_simulations_on_date"
    t.index ["game_id"], name: "index_game_simulations_on_game_id"
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

  create_table "player_season_roles", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "season_id", null: false
    t.bigint "player_id", null: false
    t.integer "team_id"
    t.string "position"
    t.integer "games_played", default: 0, null: false
    t.integer "games_started", default: 0, null: false
    t.integer "bench_games", default: 0, null: false
    t.decimal "start_rate", precision: 6, scale: 4, default: "0.0", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["player_id"], name: "index_player_season_roles_on_player_id"
    t.index ["season_id", "player_id"], name: "index_player_season_roles_on_season_id_and_player_id", unique: true
    t.index ["season_id", "team_id"], name: "index_player_season_roles_on_season_id_and_team_id"
    t.index ["season_id"], name: "index_player_season_roles_on_season_id"
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

  create_table "projection_runs", charset: "latin1", force: :cascade do |t|
    t.date "date", null: false
    t.string "model_version", default: "baseline_v1", null: false
    t.string "status", default: "running", null: false
    t.text "notes"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "projections_count", default: 0
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date", "model_version"], name: "index_projection_runs_on_date_and_model_version", unique: true
  end

  create_table "projections", charset: "latin1", force: :cascade do |t|
    t.bigint "projection_run_id", null: false
    t.bigint "player_id", null: false
    t.bigint "team_id", null: false
    t.bigint "opponent_team_id", null: false
    t.date "date", null: false
    t.float "expected_minutes"
    t.float "usage_pct"
    t.string "position"
    t.string "injury_status"
    t.float "dvp_pts_mult"
    t.float "dvp_reb_mult"
    t.float "dvp_ast_mult"
    t.float "proj_points"
    t.float "proj_rebounds"
    t.float "proj_assists"
    t.float "proj_threes"
    t.float "proj_steals"
    t.float "proj_blocks"
    t.float "proj_turnovers"
    t.float "proj_plus_minus"
    t.float "proj_pa"
    t.float "proj_pr"
    t.float "proj_ra"
    t.float "proj_pra"
    t.float "stdev_points"
    t.float "stdev_rebounds"
    t.float "stdev_assists"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.float "assist_pct"
    t.float "rebound_pct"
    t.text "explain", size: :long, collation: "utf8mb4_bin"
    t.index ["date", "opponent_team_id"], name: "index_projections_on_date_and_opponent_team_id"
    t.index ["date", "player_id"], name: "index_projections_on_date_and_player_id", unique: true
    t.index ["date", "team_id"], name: "index_projections_on_date_and_team_id"
    t.index ["opponent_team_id"], name: "index_projections_on_opponent_team_id"
    t.index ["player_id"], name: "index_projections_on_player_id"
    t.index ["projection_run_id"], name: "index_projections_on_projection_run_id"
    t.index ["team_id"], name: "index_projections_on_team_id"
    t.check_constraint "son_valid(`explain`", name: "projections_chk_1"
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

  create_table "team_advanced_stats", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.text "stats", size: :long
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "rankings", size: :long
    t.index ["season_id"], name: "index_team_advanced_stats_on_season_id"
    t.index ["team_id"], name: "index_team_advanced_stats_on_team_id"
  end

  create_table "team_advanced_stats_backup", id: false, charset: "latin1", force: :cascade do |t|
    t.bigint "id", default: 0, null: false
    t.bigint "team_id", null: false
    t.bigint "season_id", null: false
    t.text "stats", size: :long, collation: "utf8mb4_unicode_ci"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "rankings", size: :long, collation: "utf8mb4_unicode_ci"
  end

  create_table "teams", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "abbreviation"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "defense_vs_position", size: :long, collation: "utf8mb4_bin"
    t.check_constraint "son_valid(`defense_vs_position`", name: "teams_chk_1"
  end

  add_foreign_key "box_scores", "games"
  add_foreign_key "box_scores", "players"
  add_foreign_key "box_scores", "teams"
  add_foreign_key "defense_vs_positions", "seasons"
  add_foreign_key "defense_vs_positions", "teams"
  add_foreign_key "games", "teams", column: "home_team_id"
  add_foreign_key "healths", "players"
  add_foreign_key "player_season_roles", "players"
  add_foreign_key "player_season_roles", "seasons"
  add_foreign_key "player_stats", "players"
  add_foreign_key "players", "teams"
  add_foreign_key "projections", "players"
  add_foreign_key "projections", "projection_runs"
  add_foreign_key "projections", "teams"
  add_foreign_key "projections", "teams", column: "opponent_team_id"
  add_foreign_key "standings", "teams"
  add_foreign_key "team_advanced_stats", "seasons"
  add_foreign_key "team_advanced_stats", "teams"
end
