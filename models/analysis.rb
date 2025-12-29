class Analysis < ActiveRecord::Base
  validates :keyword, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # patterns and opportunities are TEXT columns, so they need serialize
  serialize :patterns, coder: JSON, type: Array
  serialize :opportunities, coder: JSON, type: Array
  # personas and raw_persona_extractions are already JSON columns, no serialize needed
end