require 'active_record'

class ScreenshotAnalysis < ActiveRecord::Base
  belongs_to :app
  
  validates :app, presence: true
  validates :screenshot_count, presence: true, numericality: { greater_than: 0 }
  validates :analysis, presence: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_app, ->(app_id) { where(app_id: app_id) }
  
  def summary
    return nil unless analysis.present?
    
    # Extract first paragraph or first 200 characters as summary
    first_paragraph = analysis.split("\n\n").first
    if first_paragraph && first_paragraph.length > 200
      first_paragraph[0..197] + "..."
    else
      first_paragraph
    end
  end
end