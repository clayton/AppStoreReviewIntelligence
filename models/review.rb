class Review < ActiveRecord::Base
  belongs_to :app
  
  validates :review_id, presence: true, uniqueness: true
  validates :rating, inclusion: { in: 1..5 }
  
  scope :low_rating, -> { where(rating: [1, 2]) }
  scope :high_rating, -> { where(rating: [4, 5]) }
  scope :recent, -> { order(published_at: :desc) }
end