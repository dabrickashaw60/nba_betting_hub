# app/models/projection_run.rb
class ProjectionRun < ApplicationRecord
  has_many :projections, dependent: :destroy
  validates :date, :model_version, presence: true

  enum status: { running: "running", success: "success", error: "error" }
end
