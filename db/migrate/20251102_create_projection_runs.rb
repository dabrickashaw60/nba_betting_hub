# db/migrate/20251102_create_projection_runs.rb
class CreateProjectionRuns < ActiveRecord::Migration[6.1]
  def change
    create_table :projection_runs do |t|
      t.date    :date, null: false
      t.string  :model_version, null: false, default: "baseline_v1"
      t.string  :status, null: false, default: "running" # running|success|error
      t.text    :notes
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :projections_count, default: 0

      t.timestamps
    end

    add_index :projection_runs, [:date, :model_version], unique: true
  end
end
