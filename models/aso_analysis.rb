require 'active_record'

class AsoAnalysis < ActiveRecord::Base
  belongs_to :app

  validates :app, presence: true
  validates :keyword, presence: true
  validates :competitor_count, presence: true, numericality: { greater_than: 0 }

  # JSON columns are already handled natively in Rails 8 - no serialize needed

  scope :recent, -> { order(created_at: :desc) }
  scope :for_keyword, ->(keyword) { where(keyword: keyword) }

  def stale?
    created_at < 7.days.ago
  end

  def summary
    return nil unless recommendations.present?
    recommendations.dig('competitive_summary', 'top_3_priorities')&.first(3)
  end
end
