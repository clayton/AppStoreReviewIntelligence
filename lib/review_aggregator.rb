require_relative 'app_store_search'
require_relative 'app_store_reviews'
require 'active_support/core_ext/numeric/time'

class ReviewAggregator
  def initialize
    @search_client = AppStoreSearch.new
    @reviews_client = AppStoreReviews.new
  end
  
  def aggregate_low_rating_reviews(keyword, limit = 10)
    puts "Searching for top #{limit} apps for keyword: #{keyword}"
    
    # Search for apps
    apps_data = @search_client.search(keyword, limit)
    
    if apps_data.empty?
      puts "No apps found for keyword: #{keyword}"
      return { apps: [], reviews: [], keyword: keyword }
    end
    
    # Save or update apps in database
    apps = save_apps(apps_data)
    
    all_reviews = []
    
    # Fetch reviews for each app
    apps.each_with_index do |app, index|
      puts "\nFetching reviews for #{app.name} (#{index + 1}/#{apps.length})..."
      
      # Check if we have recent reviews cached
      if should_fetch_new_reviews?(app)
        reviews_data = @reviews_client.fetch_low_rating_reviews(app.app_id)
        
        if reviews_data.any?
          saved_reviews = save_reviews(app, reviews_data)
          all_reviews.concat(saved_reviews)
          puts "Found #{saved_reviews.length} low-rating reviews"
        else
          puts "No low-rating reviews found"
        end
      else
        # Use cached reviews
        cached_reviews = app.reviews.low_rating.to_a
        all_reviews.concat(cached_reviews)
        puts "Using #{cached_reviews.length} cached low-rating reviews"
      end
    end
    
    {
      apps: apps,
      reviews: all_reviews,
      keyword: keyword,
      total_reviews: all_reviews.length
    }
  end
  
  private
  
  def save_apps(apps_data)
    apps_data.map do |app_data|
      app = App.find_or_initialize_by(
        app_id: app_data[:app_id],
        keyword: app_data[:keyword]
      )
      
      app.update!(app_data)
      app
    end
  end
  
  def save_reviews(app, reviews_data)
    reviews_data.map do |review_data|
      review = Review.find_or_initialize_by(review_id: review_data[:review_id])
      
      review.update!(
        app: app,
        title: review_data[:title],
        content: review_data[:content],
        rating: review_data[:rating],
        author: review_data[:author],
        version: review_data[:version],
        published_at: review_data[:published_at]
      )
      
      review
    end
  end
  
  def should_fetch_new_reviews?(app)
    # Fetch new reviews if we haven't fetched in the last 3 days
    last_review = app.reviews.order(created_at: :desc).first
    return true unless last_review
    
    last_review.created_at < 3.days.ago
  end
end