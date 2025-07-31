require 'httparty'
require 'json'

class AppScreenshots
  LOOKUP_URL = 'https://itunes.apple.com/lookup'
  
  def fetch_app_details(app_id)
    begin
      response = HTTParty.get(LOOKUP_URL, query: { id: app_id })
      
      if response.success?
        data = response.parsed_response
        data = JSON.parse(data) if data.is_a?(String)
        
        results = data['results']
        return nil if results.nil? || results.empty?
        
        app_info = results.first
        
        {
          app_id: app_id,
          app_name: app_info['trackName'],
          bundle_id: app_info['bundleId'],
          version: app_info['version'],
          artwork_url: app_info['artworkUrl512'],
          screenshot_urls: app_info['screenshotUrls'] || [],
          ipad_screenshot_urls: app_info['ipadScreenshotUrls'] || [],
          description: app_info['description'],
          release_notes: app_info['releaseNotes']
        }
      else
        puts "Failed to fetch app details for #{app_id}: #{response.code}"
        nil
      end
    rescue => e
      puts "Error fetching app details for #{app_id}: #{e.message}"
      nil
    end
  end
  
  def download_screenshot(url)
    begin
      response = HTTParty.get(url)
      
      if response.success?
        {
          url: url,
          data: response.body,
          content_type: response.headers['content-type']
        }
      else
        puts "Failed to download screenshot: #{url}"
        nil
      end
    rescue => e
      puts "Error downloading screenshot from #{url}: #{e.message}"
      nil
    end
  end
end