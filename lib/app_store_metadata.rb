require 'httparty'
require 'nokogiri'

class AppStoreMetadata
  BASE_URL = 'https://apps.apple.com'
  REQUEST_DELAY = 2 # seconds between requests

  class RateLimitError < StandardError; end

  def initialize(country: 'us')
    @country = country
    @last_request_at = nil
  end

  def fetch_metadata(app_id)
    url = build_url(app_id)

    begin
      response = fetch_with_retry(url)

      if response.success?
        parse_page(response.body, app_id)
      else
        puts "Warning: HTTP #{response.code} for app #{app_id}" if ENV['DEBUG']
        { subtitle: nil, promotional_text: nil, success: false, error: "HTTP #{response.code}" }
      end
    rescue => e
      puts "Warning: Failed to fetch metadata for app #{app_id}: #{e.message}" if ENV['DEBUG']
      { subtitle: nil, promotional_text: nil, success: false, error: e.message }
    end
  end

  def fetch_all_metadata(app_ids)
    results = {}
    app_ids.each_with_index do |app_id, index|
      puts "   Fetching metadata #{index + 1}/#{app_ids.length}..." if ENV['DEBUG']
      results[app_id] = fetch_metadata(app_id)
    end
    results
  end

  private

  def rate_limit!
    if @last_request_at
      elapsed = Time.now - @last_request_at
      sleep(REQUEST_DELAY - elapsed) if elapsed < REQUEST_DELAY
    end
    @last_request_at = Time.now
  end

  def fetch_with_retry(url, max_retries: 3)
    retries = 0
    begin
      rate_limit!
      response = HTTParty.get(url, headers: browser_headers, timeout: 10)

      raise RateLimitError, "Rate limited by Apple" if response.code == 429

      response
    rescue RateLimitError, Net::OpenTimeout, Net::ReadTimeout => e
      retries += 1
      if retries <= max_retries
        backoff = 2 ** retries
        puts "   Retrying in #{backoff}s after: #{e.message}" if ENV['DEBUG']
        sleep(backoff)
        retry
      end
      raise
    end
  end

  def browser_headers
    {
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.9',
      # Note: Don't include Accept-Encoding - HTTParty doesn't handle brotli well
      'Connection' => 'keep-alive',
      'Upgrade-Insecure-Requests' => '1'
    }
  end

  def build_url(app_id)
    "#{BASE_URL}/#{@country}/app/id#{app_id}"
  end

  def parse_page(html, app_id)
    doc = Nokogiri::HTML(html)

    # Try multiple selectors for subtitle (Apple uses Svelte with dynamic class suffixes)
    subtitle = extract_with_fallbacks(doc, [
      'h2.subtitle',                    # Current App Store structure (Svelte)
      'h2[class*="subtitle"]',          # Fallback for class variations
      '.product-header__subtitle',      # Legacy selector
      'h2.product-header__subtitle'
    ])

    # Try multiple selectors for promotional text
    promotional_text = extract_with_fallbacks(doc, [
      'p.attributes',                   # Current App Store structure
      '.section--hero .we-truncate__child',
      '.product-hero__editorial-content',
      '.section--hero p'
    ])

    # Also try to extract from JSON-LD schema
    if subtitle.nil? || promotional_text.nil?
      json_ld_data = extract_json_ld(doc)
      if json_ld_data
        subtitle ||= json_ld_data[:subtitle]
        promotional_text ||= json_ld_data[:promotional_text]
      end
    end

    puts "DEBUG: App #{app_id} - subtitle: #{subtitle&.slice(0, 30)}..., promo: #{promotional_text&.slice(0, 30)}..." if ENV['DEBUG']

    {
      subtitle: subtitle&.strip,
      promotional_text: promotional_text&.strip,
      success: subtitle.present? || promotional_text.present?
    }
  rescue Nokogiri::SyntaxError => e
    puts "Warning: HTML parsing error for app #{app_id}: #{e.message}" if ENV['DEBUG']
    { subtitle: nil, promotional_text: nil, success: false, error: e.message }
  end

  def extract_with_fallbacks(doc, selectors)
    selectors.each do |selector|
      element = doc.at_css(selector)
      text = element&.text&.strip
      return text if text.present?
    end
    nil
  end

  def extract_json_ld(doc)
    scripts = doc.css('script[type="application/ld+json"]')
    scripts.each do |script|
      begin
        data = JSON.parse(script.text)
        # Look for SoftwareApplication schema
        if data['@type'] == 'SoftwareApplication' || data['@type'] == 'MobileApplication'
          return {
            subtitle: data['alternativeHeadline'],
            promotional_text: data['description']&.slice(0, 170)
          }
        end
      rescue JSON::ParserError
        next
      end
    end
    nil
  end
end
