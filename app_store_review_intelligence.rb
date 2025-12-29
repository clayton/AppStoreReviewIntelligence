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
require_relative 'models/screenshot_analysis'
require_relative 'models/aso_analysis'

# Load lib files
require_relative 'lib/review_aggregator'
require_relative 'lib/llm_analyzer'
require_relative 'lib/persona_extractor'
require_relative 'lib/app_store_metadata'
require_relative 'lib/aso_analyzer'

class AppStoreReviewIntelligenceCLI < Thor
  desc "analyze KEYWORD", "Analyze all reviews for top apps matching KEYWORD (negative + positive)"
  option :limit, type: :numeric, default: 10, desc: "Number of top apps to analyze"
  option :country, type: :string, default: 'us', desc: "App Store country code"
  option :model, type: :string, default: LLMAnalyzer::DEFAULT_MODEL, desc: "OpenRouter model to use"
  option :force, type: :boolean, default: false, desc: "Force fresh fetch of reviews"
  option :simple, type: :boolean, default: false, desc: "Generate additional simplified summary"
  option :aso, type: :boolean, default: false, desc: "Include ASO recommendations for your app"
  option :my_app_id, type: :string, desc: "Your app's App Store ID for ASO analysis"
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
    result = aggregator.aggregate_all_reviews(keyword, options[:limit])
    
    if result[:low_reviews].empty? && result[:high_reviews].empty?
      puts "\n❌ No reviews found for keyword: #{keyword}"
      exit 1
    end
    
    puts "\n📊 Summary:"
    puts "- Found #{result[:apps].length} apps"
    puts "- Collected #{result[:total_low_reviews]} negative reviews (1-2 stars)"
    puts "- Collected #{result[:total_high_reviews]} positive reviews (4-5 stars)"
    
    # Check for recent analysis
    recent_analysis = find_recent_comprehensive_analysis(keyword, result[:total_low_reviews], result[:total_high_reviews])
    
    if recent_analysis && !options[:force]
      puts "\n📋 Using cached analysis from #{recent_analysis.created_at.strftime('%Y-%m-%d %H:%M')}"

      # Extract comprehensive analysis data from cached result
      begin
        json_match = recent_analysis.llm_analysis.match(/\{.*\}/m)
        if json_match
          parsed = JSON.parse(json_match[0])
          analysis = {
            llm_analysis: recent_analysis.llm_analysis,
            table_stakes: parsed['table_stakes'] || [],
            pain_points: parsed['pain_points'] || recent_analysis.patterns || [],
            differentiators: parsed['differentiators'] || recent_analysis.opportunities || [],
            competitive_summary: parsed['competitive_summary'] || {},
            summary: parsed['summary'] || extract_summary_from_analysis(recent_analysis),
            total_low_reviews_analyzed: parsed['total_low_reviews_analyzed'] || 0,
            total_high_reviews_analyzed: parsed['total_high_reviews_analyzed'] || 0,
            llm_model: recent_analysis.llm_model,
            personas: recent_analysis.personas || [],
            raw_persona_extractions: recent_analysis.raw_persona_extractions || [],
            insider_language: recent_analysis.insider_language || {}
          }
        else
          # Fallback for malformed cache
          analysis = {
            llm_analysis: recent_analysis.llm_analysis,
            table_stakes: [],
            pain_points: recent_analysis.patterns || [],
            differentiators: recent_analysis.opportunities || [],
            competitive_summary: {},
            summary: extract_summary_from_analysis(recent_analysis),
            total_low_reviews_analyzed: 0,
            total_high_reviews_analyzed: 0,
            llm_model: recent_analysis.llm_model,
            personas: recent_analysis.personas || [],
            raw_persona_extractions: recent_analysis.raw_persona_extractions || [],
            insider_language: recent_analysis.insider_language || {}
          }
        end
      rescue JSON::ParserError
        # Fallback for JSON parsing errors
        analysis = {
          llm_analysis: recent_analysis.llm_analysis,
          table_stakes: [],
          pain_points: recent_analysis.patterns || [],
          differentiators: recent_analysis.opportunities || [],
          competitive_summary: {},
          summary: extract_summary_from_analysis(recent_analysis),
          total_low_reviews_analyzed: 0,
          total_high_reviews_analyzed: 0,
          llm_model: recent_analysis.llm_model,
          personas: recent_analysis.personas || [],
          raw_persona_extractions: recent_analysis.raw_persona_extractions || [],
          insider_language: recent_analysis.insider_language || {}
        }
      end
    else
      # Analyze with LLM
      puts "\n🤖 Analyzing reviews with AI..."
      analyzer = LLMAnalyzer.new
      analysis = analyzer.analyze_all_reviews(result[:low_reviews], result[:high_reviews], keyword, options[:model])

      if analysis[:error]
        puts "\n❌ Analysis failed: #{analysis[:error]}"
        exit 1
      end

      # Extract and analyze personas
      all_reviews = result[:low_reviews] + result[:high_reviews]
      puts "\n👤 Identifying user personas..."
      persona_extractor = PersonaExtractor.new
      raw_personas = persona_extractor.extract_from_reviews(all_reviews)

      if raw_personas[:raw_matches].any?
        puts "   Found #{raw_personas[:raw_matches].length} unique persona phrases"
        puts "   Normalizing with AI..."
        normalized_personas = analyzer.normalize_personas(raw_personas[:raw_matches], keyword, options[:model])
        analysis[:personas] = normalized_personas[:personas] || []
        analysis[:raw_persona_extractions] = raw_personas[:raw_matches]
      else
        puts "   No persona phrases found in reviews"
        analysis[:personas] = []
        analysis[:raw_persona_extractions] = []
      end

      # Analyze insider language
      puts "\n🗣️ Analyzing insider language..."
      insider_result = analyzer.analyze_insider_language(all_reviews, keyword, options[:model])
      analysis[:insider_language] = insider_result[:insider_language] || {}

      # Save analysis
      save_comprehensive_analysis(keyword, analysis)
    end
    
    # Display results
    display_comprehensive_analysis(analysis)
    
    # Generate and display simple summary if requested
    if options[:simple]
      puts "\n🔄 Generating simplified summary..."
      simple_summary = generate_simple_summary(analysis, options[:model])
      display_simple_summary(simple_summary) if simple_summary
    end

    # Run ASO analysis if requested
    if options[:aso]
      run_aso_analysis(keyword, options[:my_app_id], result[:apps], options[:model], options[:force], options[:country])
    end
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
  
  def generate_simple_summary(analysis, model)
    # Read the simple summary prompt
    prompt_path = File.join(__dir__, 'simple_summary_prompt.txt')
    
    unless File.exist?(prompt_path)
      puts "\n❌ Error: simple_summary_prompt.txt not found"
      return nil
    end
    
    simple_prompt = File.read(prompt_path)
    
    # Prepare the research data for the simple summary
    research_data = prepare_research_data_for_simple_summary(analysis)
    
    # Use LLMAnalyzer to generate simple summary
    analyzer = LLMAnalyzer.new
    result = analyzer.generate_simple_summary(research_data, simple_prompt, model)
    
    if result[:error]
      puts "\n❌ Simple summary generation failed: #{result[:error]}"
      return nil
    end
    
    result[:summary]
  end
  
  def prepare_research_data_for_simple_summary(analysis)
    research_text = ""
    
    # Add executive summary
    if analysis[:summary]
      research_text += "EXECUTIVE SUMMARY:\n#{analysis[:summary]}\n\n"
    end
    
    # Add table stakes features
    if analysis[:table_stakes] && analysis[:table_stakes].any?
      research_text += "TABLE STAKES FEATURES (What You Need to Fit In):\n"
      analysis[:table_stakes].each_with_index do |stake, index|
        research_text += "#{index + 1}. #{stake['feature']}: #{stake['description']}\n"
      end
      research_text += "\n"
    end
    
    # Add pain points
    if analysis[:pain_points] && analysis[:pain_points].any?
      research_text += "COMMON PAIN POINTS:\n"
      analysis[:pain_points].each_with_index do |pain, index|
        research_text += "#{index + 1}. #{pain['category']}: #{pain['description']}\n"
      end
      research_text += "\n"
    end
    
    # Add differentiators
    if analysis[:differentiators] && analysis[:differentiators].any?
      research_text += "DIFFERENTIATION OPPORTUNITIES:\n"
      analysis[:differentiators].each_with_index do |diff, index|
        research_text += "#{index + 1}. #{diff['opportunity']}: #{diff['description']}\n"
      end
      research_text += "\n"
    end
    
    # Add competitive summary
    if analysis[:competitive_summary] && analysis[:competitive_summary].any?
      if analysis[:competitive_summary]['top_3_table_stakes']
        research_text += "TOP 3 FEATURES TO FIT IN:\n"
        analysis[:competitive_summary]['top_3_table_stakes'].each_with_index do |feature, index|
          research_text += "#{index + 1}. #{feature}\n"
        end
        research_text += "\n"
      end
      
      if analysis[:competitive_summary]['top_3_differentiators']
        research_text += "TOP 3 FEATURES TO STAND OUT:\n"
        analysis[:competitive_summary]['top_3_differentiators'].each_with_index do |feature, index|
          research_text += "#{index + 1}. #{feature}\n"
        end
        research_text += "\n"
      end
    end
    
    research_text
  end
  
  def display_simple_summary(summary)
    puts "\n📋 Simple Market Analysis Summary"
    puts "=" * 50
    puts summary
    puts "=" * 50
  end
  
  def find_recent_comprehensive_analysis(keyword, current_low_count, current_high_count)
    # Find the most recent analysis for this keyword
    recent = Analysis.where(keyword: keyword)
                     .where('created_at > ?', 3.days.ago)
                     .order(created_at: :desc)
                     .first
    
    return nil unless recent
    
    # For backward compatibility, check if it's a comprehensive analysis
    return nil unless recent.llm_analysis&.include?('table_stakes')
    
    # Extract review counts from the analysis
    total_reviews = (recent.total_reviews_analyzed || 0).to_i
    
    # If old format, can't compare properly
    return nil if total_reviews > 0 && !recent.llm_analysis.include?('total_low_reviews_analyzed')
    
    # For new comprehensive analyses, check both counts
    if recent.llm_analysis.include?('total_low_reviews_analyzed')
      # Try to extract counts from the stored analysis
      begin
        json_match = recent.llm_analysis.match(/\{.*\}/m)
        if json_match
          parsed = JSON.parse(json_match[0])
          stored_low = parsed['total_low_reviews_analyzed'] || 0
          stored_high = parsed['total_high_reviews_analyzed'] || 0
          
          # Check if counts haven't changed much (>10% difference)
          low_diff = (current_low_count - stored_low).abs
          high_diff = (current_high_count - stored_high).abs
          
          low_percentage = stored_low > 0 ? low_diff.to_f / stored_low * 100 : 100
          high_percentage = stored_high > 0 ? high_diff.to_f / stored_high * 100 : 100
          
          return recent if low_percentage <= 10 && high_percentage <= 10
        end
      rescue
        # If parsing fails, don't use cached analysis
      end
    end
    
    nil
  end
  
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
  
  def save_comprehensive_analysis(keyword, analysis)
    # Store comprehensive analysis with additional fields
    # We'll store table stakes and differentiators in the patterns/opportunities for backward compatibility
    Analysis.create!(
      keyword: keyword,
      llm_analysis: analysis[:llm_analysis],
      patterns: analysis[:pain_points] || analysis[:patterns] || [],
      opportunities: analysis[:differentiators] || analysis[:opportunities] || [],
      personas: analysis[:personas] || [],
      raw_persona_extractions: analysis[:raw_persona_extractions] || [],
      insider_language: analysis[:insider_language] || {},
      total_reviews_analyzed: (analysis[:total_low_reviews_analyzed] || 0) + (analysis[:total_high_reviews_analyzed] || 0),
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
  
  def display_comprehensive_analysis(analysis)
    puts "\n✨ Comprehensive Analysis Results"
    puts "=" * 50
    
    if analysis[:summary]
      puts "\n📝 Executive Summary:"
      puts analysis[:summary]
    end
    
    # Display table stakes features
    if analysis[:table_stakes] && analysis[:table_stakes].any?
      puts "\n🏛️ Table Stakes Features (What You Need to Fit In):"
      analysis[:table_stakes].each_with_index do |stake, index|
        puts "\n#{index + 1}. #{stake['feature']}"
        puts "   #{stake['description']}"
        puts "   Evidence: #{stake['evidence']}" if stake['evidence']
      end
    end
    
    # Display pain points
    if analysis[:pain_points] && analysis[:pain_points].any?
      puts "\n🔍 Common Pain Points:"
      analysis[:pain_points].each_with_index do |pain, index|
        puts "\n#{index + 1}. #{pain['category']}"
        puts "   #{pain['description']}"
        puts "   Frequency: #{pain['frequency']}" if pain['frequency']
      end
    end
    
    # Display differentiators
    if analysis[:differentiators] && analysis[:differentiators].any?
      puts "\n💡 Differentiation Opportunities:"
      analysis[:differentiators].each_with_index do |diff, index|
        puts "\n#{index + 1}. #{diff['opportunity']}"
        puts "   #{diff['description']}"
        puts "   Rationale: #{diff['rationale']}" if diff['rationale']
      end
    end

    # Display personas
    if analysis[:personas] && analysis[:personas].any?
      puts "\n👤 Target User Personas (identified from reviews):"
      analysis[:personas].each_with_index do |persona, index|
        category = persona['category'] || persona[:category]
        count = persona['count'] || persona[:count]
        description = persona['description'] || persona[:description]
        examples = persona['examples'] || persona[:examples] || []

        puts "\n#{index + 1}. #{category} (mentioned #{count} times)"
        puts "   #{description}" if description
        if examples.any?
          puts "   Examples: #{examples.first(5).map { |e| "\"#{e}\"" }.join(', ')}"
        end
      end
    end

    # Display insider language
    if analysis[:insider_language] && analysis[:insider_language].any?
      insider = analysis[:insider_language]
      has_insider = insider['has_insider_language'] || insider[:has_insider_language]
      phrases = insider['insider_phrases'] || insider[:insider_phrases] || []
      category_insight = insider['category_insight'] || insider[:category_insight]
      marketing_implications = insider['marketing_implications'] || insider[:marketing_implications]

      puts "\n🗣️ Insider Language & Phrases:"

      if has_insider && phrases.any?
        phrases.each_with_index do |phrase_data, index|
          phrase = phrase_data['phrase'] || phrase_data[:phrase]
          type = phrase_data['type'] || phrase_data[:type]
          context = phrase_data['context'] || phrase_data[:context]
          frequency = phrase_data['frequency'] || phrase_data[:frequency]

          puts "\n#{index + 1}. \"#{phrase}\" [#{type}]"
          puts "   #{context}" if context
          puts "   Frequency: #{frequency}" if frequency
        end
      else
        puts "\n   No strong insider language detected."
      end

      if category_insight
        puts "\n   Category Insight: #{category_insight}"
      end

      if marketing_implications
        puts "\n   Marketing Implications: #{marketing_implications}"
      end
    end

    # Display competitive summary
    if analysis[:competitive_summary] && analysis[:competitive_summary].any?
      puts "\n🎯 Competitive Positioning Summary:"
      puts "=" * 40
      
      if analysis[:competitive_summary]['top_3_table_stakes']
        puts "\n✅ Top 3 Features to FIT IN (Table Stakes):"
        analysis[:competitive_summary]['top_3_table_stakes'].each_with_index do |feature, index|
          puts "   #{index + 1}. #{feature}"
        end
      end
      
      if analysis[:competitive_summary]['top_3_differentiators']
        puts "\n🚀 Top 3 Features to STAND OUT (Differentiators):"
        analysis[:competitive_summary]['top_3_differentiators'].each_with_index do |feature, index|
          puts "   #{index + 1}. #{feature}"
        end
      end
    end
    
    puts "\n" + "=" * 50
    puts "Low-rating reviews analyzed: #{analysis[:total_low_reviews_analyzed] || 0}"
    puts "High-rating reviews analyzed: #{analysis[:total_high_reviews_analyzed] || 0}"
    puts "Total reviews analyzed: #{(analysis[:total_low_reviews_analyzed] || 0) + (analysis[:total_high_reviews_analyzed] || 0)}"
    puts "Model used: #{analysis[:llm_model]}"
  end

  def run_aso_analysis(keyword, user_app_id, competitor_apps, model, force, country)
    if user_app_id.nil? || user_app_id.empty?
      puts "\n❌ Error: --my-app-id is required for ASO analysis"
      puts "Usage: ./app_store_review_intelligence.rb analyze \"keyword\" --aso --my-app-id=123456789"
      return
    end

    puts "\n🎯 Starting App Store Optimization Analysis..."
    puts "=" * 50

    # Find or create app record for user's app
    user_app = find_or_fetch_user_app(user_app_id, keyword)

    unless user_app
      puts "❌ Error: Could not fetch your app details for ID: #{user_app_id}"
      return
    end

    puts "📱 Your app: #{user_app.name}"

    # Check for cached analysis
    unless force
      recent_analysis = find_recent_aso_analysis(user_app, keyword, competitor_apps.length)
      if recent_analysis
        puts "📋 Using cached ASO analysis from #{recent_analysis.created_at.strftime('%Y-%m-%d %H:%M')}"
        display_aso_analysis(recent_analysis)
        return
      end
    end

    # Fetch metadata from web pages
    puts "🌐 Scraping App Store metadata..."
    metadata_fetcher = AppStoreMetadata.new(country: country)

    # Get user's app web metadata
    user_web_metadata = metadata_fetcher.fetch_metadata(user_app_id)

    # Get competitor web metadata
    competitor_app_ids = competitor_apps.map(&:app_id)
    competitor_web_metadata = metadata_fetcher.fetch_all_metadata(competitor_app_ids)

    # Build combined metadata
    user_metadata = build_app_metadata(user_app, user_web_metadata)
    competitor_metadata = competitor_apps.map.with_index do |app, index|
      web_data = competitor_web_metadata[app.app_id] || {}
      build_app_metadata(app, web_data).merge(rank: index + 1)
    end

    # Run LLM analysis
    puts "🤖 Analyzing with #{model}..."
    analyzer = AsoAnalyzer.new
    result = analyzer.analyze(user_metadata, competitor_metadata, keyword, model)

    if result[:error]
      puts "❌ ASO analysis failed: #{result[:error]}"
      return
    end

    # Save analysis
    aso_analysis = AsoAnalysis.create!(
      app: user_app,
      keyword: keyword,
      competitor_count: competitor_apps.length,
      competitor_app_ids: competitor_app_ids,
      llm_analysis: result[:llm_analysis],
      recommendations: result[:recommendations],
      llm_model: result[:llm_model]
    )

    puts "✅ ASO analysis saved"
    display_aso_analysis(aso_analysis)
  end

  def find_or_fetch_user_app(app_id, keyword)
    # Check if we have the app cached
    existing = App.find_by(app_id: app_id)
    return existing if existing

    # Fetch from iTunes API
    puts "   Fetching your app from iTunes..."
    itunes_url = "https://itunes.apple.com/lookup?id=#{app_id}"

    begin
      response = HTTParty.get(itunes_url, timeout: 10)
      return nil unless response.success?

      data = response.parsed_response
      data = JSON.parse(data) if data.is_a?(String)

      app_info = data.dig('results', 0)
      return nil unless app_info

      App.create!(
        app_id: app_id,
        name: app_info['trackName'],
        developer: app_info['artistName'],
        bundle_id: app_info['bundleId'],
        price: app_info['price'],
        currency: app_info['currency'],
        average_rating: app_info['averageUserRating'],
        rating_count: app_info['userRatingCount'],
        version: app_info['version'],
        description: app_info['description'],
        icon_url: app_info['artworkUrl512'] || app_info['artworkUrl100'],
        keyword: keyword,
        search_rank: 0 # User's app, not from search results
      )
    rescue => e
      puts "Warning: Failed to fetch app #{app_id}: #{e.message}" if ENV['DEBUG']
      nil
    end
  end

  def build_app_metadata(app, web_metadata)
    {
      name: app.name,
      subtitle: web_metadata[:subtitle],
      promotional_text: web_metadata[:promotional_text],
      description: app.description,
      category: nil,
      rating: app.average_rating,
      rating_count: app.rating_count
    }
  end

  def find_recent_aso_analysis(user_app, keyword, current_competitor_count)
    recent = AsoAnalysis.where(app: user_app, keyword: keyword)
                        .where('created_at > ?', 7.days.ago)
                        .order(created_at: :desc)
                        .first

    return nil unless recent

    # Check if competitor count changed significantly (>20%)
    stored_count = recent.competitor_count
    return recent if stored_count == 0

    diff_percentage = ((current_competitor_count - stored_count).abs.to_f / stored_count) * 100
    diff_percentage <= 20 ? recent : nil
  end

  def display_aso_analysis(analysis)
    recs = analysis.recommendations || {}

    puts "\n" + "=" * 60
    puts "🎯 APP STORE OPTIMIZATION RECOMMENDATIONS"
    puts "=" * 60
    puts "Keyword: #{analysis.keyword}"
    puts "Competitors analyzed: #{analysis.competitor_count}"
    puts "Model: #{analysis.llm_model}"
    puts "Generated: #{analysis.created_at.strftime('%Y-%m-%d %H:%M')}"

    if recs['name_recommendations']
      puts "\n📛 NAME OPTIMIZATION"
      puts "-" * 40
      puts "Analysis: #{recs['name_recommendations']['current_analysis']}"
      if recs['name_recommendations']['suggestions']&.any?
        puts "\nSuggestions:"
        recs['name_recommendations']['suggestions'].each_with_index { |s, i| puts "  #{i + 1}. #{s}" }
      end
      if recs['name_recommendations']['keywords_to_include']&.any?
        puts "\nKeywords to include: #{recs['name_recommendations']['keywords_to_include'].join(', ')}"
      end
    end

    if recs['subtitle_recommendations']
      puts "\n📝 SUBTITLE OPTIMIZATION"
      puts "-" * 40
      puts "Analysis: #{recs['subtitle_recommendations']['current_analysis']}"
      if recs['subtitle_recommendations']['suggested_subtitles']&.any?
        puts "\nSuggested subtitles (max 30 chars):"
        recs['subtitle_recommendations']['suggested_subtitles'].each_with_index do |s, i|
          char_count = s&.length || 0
          puts "  #{i + 1}. \"#{s}\" (#{char_count} chars)"
        end
      end
      puts "\nCompetitor patterns: #{recs['subtitle_recommendations']['competitor_patterns']}" if recs['subtitle_recommendations']['competitor_patterns']
    end

    if recs['promotional_text_recommendations']
      puts "\n📣 PROMOTIONAL TEXT"
      puts "-" * 40
      puts "Analysis: #{recs['promotional_text_recommendations']['current_analysis']}"
      if recs['promotional_text_recommendations']['suggested_text']
        puts "\nSuggested text (max 170 chars):"
        puts "  \"#{recs['promotional_text_recommendations']['suggested_text']}\""
      end
      if recs['promotional_text_recommendations']['key_themes']&.any?
        puts "\nKey themes: #{recs['promotional_text_recommendations']['key_themes'].join(', ')}"
      end
    end

    if recs['keyword_recommendations']
      puts "\n🔑 KEYWORD STRATEGY"
      puts "-" * 40
      kr = recs['keyword_recommendations']
      puts "Primary keywords: #{kr['primary_keywords']&.join(', ')}" if kr['primary_keywords']&.any?
      puts "Secondary keywords: #{kr['secondary_keywords']&.join(', ')}" if kr['secondary_keywords']&.any?
      puts "Competitor keywords: #{kr['competitor_keywords']&.join(', ')}" if kr['competitor_keywords']&.any?
      puts "Gap keywords (opportunities): #{kr['gap_keywords']&.join(', ')}" if kr['gap_keywords']&.any?
    end

    if recs['description_recommendations']
      puts "\n📄 DESCRIPTION OPTIMIZATION"
      puts "-" * 40
      puts "Analysis: #{recs['description_recommendations']['current_analysis']}"
      if recs['description_recommendations']['suggested_opening']
        puts "\nSuggested opening paragraph:"
        puts "  #{recs['description_recommendations']['suggested_opening']}"
      end
      if recs['description_recommendations']['key_features_to_highlight']&.any?
        puts "\nKey features to highlight:"
        recs['description_recommendations']['key_features_to_highlight'].each { |f| puts "  - #{f}" }
      end
      if recs['description_recommendations']['keyword_placement_tips']
        puts "\nKeyword placement: #{recs['description_recommendations']['keyword_placement_tips']}"
      end
    end

    if recs['competitive_summary']
      puts "\n🏆 COMPETITIVE SUMMARY"
      puts "-" * 40
      puts "Your position: #{recs['competitive_summary']['your_current_position']}"
      if recs['competitive_summary']['top_3_priorities']&.any?
        puts "\nTop 3 Priorities:"
        recs['competitive_summary']['top_3_priorities'].each_with_index { |p, i| puts "  #{i + 1}. #{p}" }
      end
      if recs['competitive_summary']['unique_angles']&.any?
        puts "\nUnique positioning angles:"
        recs['competitive_summary']['unique_angles'].each { |a| puts "  - #{a}" }
      end
    end

    puts "\n" + "=" * 60
  end
end

# Run the CLI
AppStoreReviewIntelligenceCLI.start(ARGV) if __FILE__ == $0