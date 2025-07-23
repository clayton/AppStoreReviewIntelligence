class App < ActiveRecord::Base
  has_many :reviews, dependent: :destroy
  
  validates :app_id, presence: true, uniqueness: { scope: :keyword }
  validates :name, presence: true
  validates :keyword, presence: true
end