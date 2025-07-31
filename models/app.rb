require 'active_record'

class App < ActiveRecord::Base
  has_many :reviews, dependent: :destroy
  has_many :screenshot_analyses, dependent: :destroy
  
  validates :app_id, presence: true, uniqueness: { scope: :keyword }
  validates :name, presence: true
  validates :keyword, presence: true
end