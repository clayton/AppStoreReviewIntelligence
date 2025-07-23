require 'httparty'
require 'json'

class AppStoreSearch
  BASE_URL = 'https://itunes.apple.com/search'
  
  def initialize
    @cache_duration = 3600 # 1 hour
  end
  
  def search(keyword, limit = 10, country = 'us')
    params = {
      term: keyword,
      country: country,
      entity: 'software',
      limit: limit
    }
    
    response = HTTParty.get(BASE_URL, query: params)
    
    if response.success?
      # Force JSON parsing if response is a string
      parsed = response.parsed_response
      if parsed.is_a?(String)
        parsed = JSON.parse(parsed)
      end
      puts "DEBUG: Response type: #{parsed.class}" if ENV['DEBUG']
      puts "DEBUG: Results count: #{parsed['resultCount']}" if ENV['DEBUG'] && parsed.is_a?(Hash)
      parse_results(parsed, keyword)
    else
      raise "App Store API error: #{response.code} - #{response.message}"
    end
  end
  
  private
  
  def parse_results(data, keyword)
    return [] unless data.is_a?(Hash) && data['results'].is_a?(Array)
    
    data['results'].map.with_index do |app_data, index|
      {
        app_id: app_data['trackId'].to_s,
        name: app_data['trackName'],
        developer: app_data['artistName'],
        bundle_id: app_data['bundleId'],
        price: app_data['price'],
        currency: app_data['currency'],
        average_rating: app_data['averageUserRating'],
        rating_count: app_data['userRatingCount'],
        version: app_data['version'],
        description: app_data['description'],
        icon_url: app_data['artworkUrl512'] || app_data['artworkUrl100'],
        keyword: keyword,
        search_rank: index + 1
      }
    end
  end
end