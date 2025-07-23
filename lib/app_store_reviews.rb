require 'httparty'
require 'json'

class AppStoreReviews
  RSS_BASE_URL = 'https://itunes.apple.com'
  
  def initialize
    @delay = 1 # Delay between requests to avoid rate limiting
  end
  
  def fetch_reviews(app_id, country = 'us', max_pages = 10)
    all_reviews = []
    
    (1..max_pages).each do |page|
      url = "#{RSS_BASE_URL}/#{country}/rss/customerreviews/page=#{page}/id=#{app_id}/sortBy=mostRecent/json"
      
      begin
        response = HTTParty.get(url)
        
        if response.success?
          data = response.parsed_response
          # Force JSON parsing if response is a string
          if data.is_a?(String)
            data = JSON.parse(data)
          end
          entries = data.dig('feed', 'entry') || []
          
          # First entry is often app info, not a review
          entries = entries.is_a?(Array) ? entries : [entries]
          
          break if entries.empty?
          
          entries.each do |entry|
            review = parse_review_entry(entry, app_id)
            all_reviews << review if review
          end
        else
          puts "Failed to fetch reviews page #{page} for app #{app_id}: #{response.code}"
          break
        end
        
        sleep(@delay) # Throttle requests
      rescue => e
        puts "Error fetching reviews for app #{app_id}, page #{page}: #{e.message}"
        break
      end
    end
    
    all_reviews
  end
  
  def fetch_low_rating_reviews(app_id, country = 'us', max_pages = 10)
    reviews = fetch_reviews(app_id, country, max_pages)
    reviews.select { |r| r[:rating] && r[:rating] <= 2 }
  end
  
  private
  
  def parse_review_entry(entry, app_id)
    # Skip if it's not a review (first entry is often app info)
    return nil unless entry['im:rating']
    
    {
      app_id: app_id,
      review_id: entry['id']&.dig('label'),
      title: entry['title']&.dig('label'),
      content: entry['content']&.dig('label'),
      rating: entry['im:rating']&.dig('label')&.to_i,
      author: entry['author']&.dig('name', 'label'),
      version: entry['im:version']&.dig('label'),
      published_at: parse_date(entry['updated']&.dig('label'))
    }
  rescue => e
    puts "Error parsing review entry: #{e.message}"
    nil
  end
  
  def parse_date(date_string)
    return nil unless date_string
    DateTime.parse(date_string)
  rescue
    nil
  end
end