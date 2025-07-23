class Analysis < ActiveRecord::Base
  validates :keyword, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  
  serialize :patterns, coder: JSON, type: Array
  serialize :opportunities, coder: JSON, type: Array
end