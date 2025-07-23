#!/usr/bin/env ruby

require 'bundler/setup'
require 'thor'
require 'active_record'
require 'dotenv/load'
require 'json'

# Load database configuration
require_relative 'db/config'
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'db/app_store_reviews.sqlite3'
)

# Load models
require_relative 'models/app'
require_relative 'models/review'
require_relative 'models/analysis'

# Load lib files
require_relative 'lib/review_aggregator'
require_relative 'lib/llm_analyzer'

class AppStoreReviewIntelligenceCLI < Thor
  desc "analyze KEYWORD", "Analyze negative reviews for top apps matching KEYWORD"
  option :limit, type: :numeric, default: 10, desc: "Number of top apps to analyze"
  option :country, type: :string, default: 'us', desc: "App Store country code"
  option :model, type: :string, default: LLMAnalyzer::DEFAULT_MODEL, desc: "OpenRouter model to use"
  option :force, type: :boolean, default: false, desc: "Force fresh fetch of reviews"
  def analyze(keyword)
    ensure_api_key!
    
    puts "\n🔍 App Store Review Intelligence"
    puts "=" * 50
    
    # Clear cache if forced
    if options[:force]
      puts "Forcing fresh data fetch..."
      App.where(keyword: keyword).destroy_all
    end
    
    # Aggregate reviews
    aggregator = ReviewAggregator.new
    result = aggregator.aggregate_low_rating_reviews(keyword, options[:limit])
    
    if result[:reviews].empty?
      puts "\n❌ No negative reviews found for keyword: #{keyword}"
      exit 1
    end
    
    puts "\n📊 Summary:"
    puts "- Found #{result[:apps].length} apps"
    puts "- Collected #{result[:total_reviews]} negative reviews"
    
    # Check for recent analysis
    recent_analysis = find_recent_analysis(keyword, result[:total_reviews])
    
    if recent_analysis && !options[:force]
      puts "\n📋 Using cached analysis from #{recent_analysis.created_at.strftime('%Y-%m-%d %H:%M')}"
      analysis = {
        llm_analysis: recent_analysis.llm_analysis,
        patterns: recent_analysis.patterns,
        opportunities: recent_analysis.opportunities,
        summary: extract_summary_from_analysis(recent_analysis),
        total_reviews_analyzed: recent_analysis.total_reviews_analyzed,
        llm_model: recent_analysis.llm_model
      }
    else
      # Analyze with LLM
      puts "\n🤖 Analyzing reviews with AI..."
      analyzer = LLMAnalyzer.new
      analysis = analyzer.analyze_reviews(result[:reviews], keyword, options[:model])
      
      if analysis[:error]
        puts "\n❌ Analysis failed: #{analysis[:error]}"
        exit 1
      end
      
      # Save analysis
      save_analysis(keyword, analysis)
    end
    
    # Display results
    display_analysis(analysis)
  end
  
  desc "history KEYWORD", "Show past analyses for KEYWORD"
  def history(keyword)
    analyses = Analysis.where(keyword: keyword).recent.limit(10)
    
    if analyses.empty?
      puts "\n❌ No analysis history found for keyword: #{keyword}"
      exit 1
    end
    
    puts "\n📜 Analysis History for '#{keyword}'"
    puts "=" * 50
    
    analyses.each_with_index do |analysis, index|
      puts "\n#{index + 1}. #{analysis.created_at.strftime('%Y-%m-%d %H:%M')}"
      puts "   Reviews analyzed: #{analysis.total_reviews_analyzed}"
      puts "   Model: #{analysis.llm_model}"
      
      if analysis.patterns.any?
        puts "   Patterns found: #{analysis.patterns.length}"
      end
      
      if analysis.opportunities.any?
        puts "   Opportunities: #{analysis.opportunities.length}"
      end
    end
  end
  
  desc "show ID", "Show details of a specific analysis"
  def show(id)
    analysis = Analysis.find_by(id: id)
    
    if analysis.nil?
      puts "\n❌ Analysis not found with ID: #{id}"
      exit 1
    end
    
    display_analysis(analysis.attributes.symbolize_keys)
  end
  
  desc "apps KEYWORD", "List cached apps for KEYWORD"
  def apps(keyword)
    apps = App.where(keyword: keyword).order(search_rank: :asc)
    
    if apps.empty?
      puts "\n❌ No cached apps found for keyword: #{keyword}"
      puts "Run 'analyze #{keyword}' first to fetch data."
      exit 1
    end
    
    puts "\n📱 Apps for '#{keyword}'"
    puts "=" * 50
    
    apps.each do |app|
      review_count = app.reviews.low_rating.count
      puts "\n#{app.search_rank}. #{app.name}"
      puts "   Developer: #{app.developer}"
      puts "   Rating: #{app.average_rating}/5 (#{app.rating_count} reviews)"
      puts "   Negative reviews cached: #{review_count}"
    end
  end
  
  private
  
  def find_recent_analysis(keyword, current_review_count)
    # Find the most recent analysis for this keyword
    recent = Analysis.where(keyword: keyword)
                     .where('created_at > ?', 3.days.ago)
                     .order(created_at: :desc)
                     .first
    
    return nil unless recent
    
    # Check if the review count has changed significantly (>10% difference)
    review_diff = (current_review_count - recent.total_reviews_analyzed).abs
    percentage_diff = review_diff.to_f / recent.total_reviews_analyzed * 100
    
    # Return the analysis if review count hasn't changed much
    percentage_diff <= 10 ? recent : nil
  end
  
  def extract_summary_from_analysis(analysis)
    return nil unless analysis.llm_analysis
    
    # Try to extract summary from the stored JSON
    content = analysis.llm_analysis
    
    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if content.include?('```')
    
    # Try to parse the JSON and extract summary
    begin
      json_match = content.match(/\{.*\}/m)
      if json_match
        parsed = JSON.parse(json_match[0])
        return parsed['summary']
      end
    rescue JSON::ParserError
      # Fall back to regex extraction
      json_match = content.match(/"summary"\s*:\s*"([^"]+(?:\\.[^"]+)*)"/m)
      return json_match[1].gsub(/\\(.)/, '\1') if json_match
    end
    
    nil
  end
  
  def ensure_api_key!
    if ENV['OPENROUTER_API_KEY'].nil? || ENV['OPENROUTER_API_KEY'].empty?
      puts "\n❌ Error: OPENROUTER_API_KEY not set"
      puts "Please set your OpenRouter API key in the .env file"
      puts "Copy .env.example to .env and add your key"
      exit 1
    end
  end
  
  def save_analysis(keyword, analysis)
    Analysis.create!(
      keyword: keyword,
      llm_analysis: analysis[:llm_analysis],
      patterns: analysis[:patterns],
      opportunities: analysis[:opportunities],
      total_reviews_analyzed: analysis[:total_reviews_analyzed],
      llm_model: analysis[:llm_model]
    )
  end
  
  def display_analysis(analysis)
    puts "\n✨ Analysis Results"
    puts "=" * 50
    
    if analysis[:summary]
      puts "\n📝 Summary:"
      puts analysis[:summary]
    end
    
    if analysis[:patterns] && analysis[:patterns].any?
      puts "\n🔍 Common Patterns:"
      analysis[:patterns].each_with_index do |pattern, index|
        puts "\n#{index + 1}. #{pattern['category']}"
        puts "   #{pattern['description']}"
        puts "   Frequency: #{pattern['frequency']}"
        
        if pattern['examples'] && pattern['examples'].any?
          puts "   Examples:"
          pattern['examples'].first(2).each do |example|
            puts "   - #{example[0..100]}..."
          end
        end
      end
    end
    
    if analysis[:opportunities] && analysis[:opportunities].any?
      puts "\n💡 Opportunities:"
      analysis[:opportunities].each_with_index do |opp, index|
        puts "\n#{index + 1}. #{opp['title']} (Priority: #{opp['priority']})"
        puts "   #{opp['description']}"
        
        if opp['implementation_notes']
          puts "   Implementation: #{opp['implementation_notes']}"
        end
      end
    end
    
    puts "\n" + "=" * 50
    puts "Reviews analyzed: #{analysis[:total_reviews_analyzed]}"
    puts "Model used: #{analysis[:llm_model]}"
  end
end

# Run the CLI
AppStoreReviewIntelligenceCLI.start(ARGV) if __FILE__ == $0