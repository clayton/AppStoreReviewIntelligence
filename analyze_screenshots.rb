#!/usr/bin/env ruby

require 'bundler/setup'
require 'thor'
require 'active_record'
require 'dotenv/load'
require 'active_support/core_ext/numeric/time'

# Load database configuration
require_relative 'db/config'
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'db/app_store_reviews.sqlite3'
)

# Load models
require_relative 'models/app'
require_relative 'models/screenshot_analysis'

# Load libraries
require_relative 'lib/app_store_search'
require_relative 'lib/app_screenshots'
require_relative 'lib/screenshot_analyzer'

class ScreenshotAnalysisCLI < Thor
  desc "analyze KEYWORD", "Analyze screenshots for top apps matching KEYWORD"
  option :limit, type: :numeric, default: 10, desc: "Number of top apps to analyze"
  option :country, type: :string, default: 'us', desc: "App Store country code"
  option :force, type: :boolean, default: false, desc: "Force fresh analysis even if cached"
  def analyze(keyword)
    ensure_api_key!
    
    puts "\n📸 App Store Screenshot Intelligence"
    puts "=" * 50
    puts "Keyword: #{keyword}"
    puts "Apps to analyze: #{options[:limit]}"
    puts "Country: #{options[:country]}"
    puts
    
    # Get apps for keyword
    apps = get_or_fetch_apps(keyword, options[:limit], options[:country])
    
    if apps.empty?
      puts "\n❌ No apps found for keyword: #{keyword}"
      exit 1
    end
    
    # Initialize services
    @screenshot_fetcher = AppScreenshots.new
    @analyzer = ScreenshotAnalyzer.new
    
    # Analyze screenshots for each app
    apps.each_with_index do |app, index|
      puts "\n[#{index + 1}/#{apps.length}] #{app.name} (#{app.app_id})"
      puts "-" * 40
      
      # Check for existing analysis
      if !options[:force] && (existing_analysis = get_recent_analysis(app))
        puts "✓ Using cached analysis from #{existing_analysis.created_at.strftime('%Y-%m-%d %H:%M')}"
        display_analysis(existing_analysis)
        next
      end
      
      # Fetch and analyze screenshots
      begin
        app_details = @screenshot_fetcher.fetch_app_details(app.app_id)
        
        if app_details.nil?
          puts "❌ Failed to fetch app details"
          next
        end
        
        screenshot_urls = app_details[:screenshot_urls]
        
        if screenshot_urls.empty?
          puts "❌ No screenshots found for this app"
          next
        end
        
        puts "Found #{screenshot_urls.length} screenshots"
        puts "Analyzing with OpenRouter (#{ScreenshotAnalyzer::DEFAULT_MODEL})..."
        
        analysis_result = @analyzer.analyze_screenshots(app.name, screenshot_urls)
        
        if analysis_result.nil?
          puts "❌ Failed to analyze screenshots"
          next
        end
        
        # Save to database
        screenshot_analysis = ScreenshotAnalysis.create!(
          app: app,
          screenshot_count: analysis_result[:screenshot_count],
          analysis: analysis_result[:analysis],
          screenshot_urls: analysis_result[:screenshot_urls]
        )
        
        puts "✓ Analysis saved"
        display_analysis(screenshot_analysis)
        
      rescue => e
        puts "❌ Error: #{e.message}"
        puts e.backtrace.first(3) if ENV['DEBUG']
      end
      
      # Rate limiting
      sleep(2) unless index == apps.length - 1
    end
    
    puts "\n" + "=" * 50
    puts "✓ Screenshot analysis complete!"
  end
  
  desc "compare COMPETITOR_PATH YOUR_PATH", "Compare your screenshots against competitor screenshots"
  option :competitor_name, type: :string, default: "Competitor", desc: "Name of the competitor app"
  def compare(competitor_path, local_path)
    ensure_api_key!

    # Validate competitor path exists
    unless File.directory?(competitor_path)
      puts "\n[ERROR] Competitor path does not exist or is not a directory: #{competitor_path}"
      exit 1
    end

    # Validate local path exists
    unless File.directory?(local_path)
      puts "\n[ERROR] Your screenshots path does not exist or is not a directory: #{local_path}"
      exit 1
    end

    puts "\n[COMPARE] Screenshot Comparison Analysis"
    puts "=" * 50
    puts "Competitor: #{options[:competitor_name]}"
    puts "Competitor Screenshots: #{competitor_path}"
    puts "Your Screenshots: #{local_path}"
    puts

    @analyzer = ScreenshotAnalyzer.new

    # Load competitor screenshots
    puts "[FOLDER] Loading competitor screenshots..."
    competitor_screenshots = @analyzer.load_local_screenshots(competitor_path)

    if competitor_screenshots.empty?
      puts "\n[ERROR] No image files found in #{competitor_path}"
      puts "Supported formats: .png, .jpg, .jpeg"
      exit 1
    end

    puts "[OK] Found #{competitor_screenshots.length} competitor screenshots"

    # Load local screenshots
    puts "\n[FOLDER] Loading your screenshots..."
    local_screenshots = @analyzer.load_local_screenshots(local_path)

    if local_screenshots.empty?
      puts "\n[ERROR] No image files found in #{local_path}"
      puts "Supported formats: .png, .jpg, .jpeg"
      exit 1
    end

    puts "[OK] Found #{local_screenshots.length} of your screenshots"

    # Run comparison analysis
    puts "\n[AI] Analyzing with #{ScreenshotAnalyzer::DEFAULT_MODEL}..."
    result = @analyzer.compare_local_screenshots(
      options[:competitor_name],
      competitor_screenshots,
      local_screenshots
    )

    if result.nil?
      puts "\n[ERROR] Analysis failed"
      exit 1
    end

    # Display results
    display_comparison_result(result)
  end

  desc "history KEYWORD", "Show past screenshot analyses for KEYWORD"
  def history(keyword)
    apps = App.where(keyword: keyword)
    
    if apps.empty?
      puts "\n❌ No apps found for keyword: #{keyword}"
      exit 1
    end
    
    puts "\n📜 Screenshot Analysis History for '#{keyword}'"
    puts "=" * 50
    
    apps.each do |app|
      analyses = app.screenshot_analyses.recent.limit(5)
      next if analyses.empty?
      
      puts "\n#{app.name}:"
      analyses.each do |analysis|
        puts "  - #{analysis.created_at.strftime('%Y-%m-%d %H:%M')} - #{analysis.screenshot_count} screenshots"
      end
    end
  end
  
  private
  
  def ensure_api_key!
    unless ENV['OPENROUTER_API_KEY']
      puts "\n❌ Error: OPENROUTER_API_KEY environment variable not set"
      puts "Please set it with: export OPENROUTER_API_KEY='your-api-key'"
      exit 1
    end
  end
  
  def get_or_fetch_apps(keyword, limit, country)
    # Check for recent apps with this keyword
    recent_apps = App.where(keyword: keyword)
                    .where('created_at > ?', 2.days.ago)
                    .order(created_at: :desc)
                    .limit(limit)
    
    if recent_apps.count >= limit
      puts "✓ Using cached app list (#{recent_apps.count} apps)"
      return recent_apps
    end
    
    # Fetch fresh app list
    puts "🔍 Searching App Store for '#{keyword}'..."
    search_client = AppStoreSearch.new
    apps_data = search_client.search(keyword, limit, country)
    
    if apps_data.empty?
      return []
    end
    
    # Save apps to database
    apps = []
    apps_data.each do |app_data|
      app = App.find_or_create_by(
        app_id: app_data[:app_id],
        keyword: keyword
      ) do |a|
        a.name = app_data[:name]
        a.developer = app_data[:developer]
        a.bundle_id = app_data[:bundle_id]
        a.version = app_data[:version]
        a.average_rating = app_data[:rating]
        a.rating_count = app_data[:ratings_count]
      end
      
      # Update if exists
      if app.persisted? && app.created_at < 2.days.ago
        app.update!(
          name: app_data[:name],
          developer: app_data[:developer],
          version: app_data[:version],
          average_rating: app_data[:rating],
          rating_count: app_data[:ratings_count]
        )
      end
      
      apps << app
    end
    
    puts "✓ Found #{apps.length} apps"
    apps
  end
  
  def get_recent_analysis(app)
    # Check for analysis within last 7 days
    app.screenshot_analyses
       .where('created_at > ?', 7.days.ago)
       .order(created_at: :desc)
       .first
  end
  
  def display_analysis(analysis)
    puts "\n📊 Analysis Results:"
    puts "Screenshots analyzed: #{analysis.screenshot_count}"
    puts "\n#{analysis.analysis}"
  end

  def parse_app_store_url(url)
    match = url.match(/id(\d+)/)
    match ? match[1] : nil
  end

  def display_comparison_result(result)
    puts "\n" + "=" * 50
    puts "[RESULTS] SCREENSHOT COMPARISON"
    puts "=" * 50
    puts "Competitor: #{result[:competitor_name]}"
    puts "Competitor screenshots: #{result[:competitor_screenshot_count]}"
    puts "Your screenshots: #{result[:local_screenshot_count]}"
    puts "Model: #{result[:llm_model]}"
    puts "=" * 50
    puts "\n#{result[:analysis]}"
    puts "\n" + "=" * 50
  end
end

# Run the CLI
ScreenshotAnalysisCLI.start(ARGV) if __FILE__ == $0