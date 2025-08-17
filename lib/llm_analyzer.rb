require 'open_router'
require 'json'

class LLMAnalyzer
  DEFAULT_MODEL = 'google/gemini-2.5-pro'
  
  def initialize
    @client = OpenRouter::Client.new(
      access_token: ENV['OPENROUTER_API_KEY']
    )
  end
  
  def analyze_reviews(reviews, keyword, model = DEFAULT_MODEL)
    return { error: "No reviews to analyze" } if reviews.empty?
    
    prompt = build_analysis_prompt(reviews, keyword)
    
    begin
      messages = [
        {
          role: "system",
          content: "You are an expert product analyst specializing in mobile app user experience and market opportunities."
        },
        {
          role: "user",
          content: prompt
        }
      ]
      
      response = @client.complete(messages, 
        model: model,
        extras: {
          temperature: 0.7
        }
      )
      
      # Log response for debugging only when DEBUG env var is set
      if ENV['DEBUG']
        puts "\nDEBUG: LLM Response class: #{response.class}"
        puts "DEBUG: LLM Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: LLM Response sample: #{response.inspect[0..1000]}"
      end
      
      parse_analysis_response(response, reviews.length, model)
    rescue => e
      { error: "LLM analysis failed: #{e.message}" }
    end
  end
  
  def analyze_all_reviews(low_reviews, high_reviews, keyword, model = DEFAULT_MODEL)
    return { error: "No reviews to analyze" } if low_reviews.empty? && high_reviews.empty?
    
    prompt = build_comprehensive_analysis_prompt(low_reviews, high_reviews, keyword)
    
    begin
      messages = [
        {
          role: "system",
          content: "You are an expert product analyst specializing in mobile app user experience, market opportunities, and competitive positioning."
        },
        {
          role: "user",
          content: prompt
        }
      ]
      
      response = @client.complete(messages, 
        model: model,
        extras: {
          temperature: 0.7
        }
      )
      
      if ENV['DEBUG']
        puts "\nDEBUG: LLM Response class: #{response.class}"
        puts "DEBUG: LLM Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: LLM Response sample: #{response.inspect[0..1000]}"
      end
      
      parse_comprehensive_analysis_response(response, low_reviews.length, high_reviews.length, model)
    rescue => e
      { error: "LLM analysis failed: #{e.message}" }
    end
  end
  
  def generate_simple_summary(research_data, simple_prompt, model = DEFAULT_MODEL)
    return { error: "No research data provided" } if research_data.nil? || research_data.empty?
    
    full_prompt = "#{simple_prompt}\n\nRESEARCH DATA:\n#{research_data}"
    
    begin
      messages = [
        {
          role: "system",
          content: "You are a concise business analyst who explains complex market research in simple, direct language."
        },
        {
          role: "user",
          content: full_prompt
        }
      ]
      
      response = @client.complete(messages, 
        model: model,
        extras: {
          temperature: 0.5  # Lower temperature for more focused output
        }
      )
      
      if ENV['DEBUG']
        puts "\nDEBUG: Simple Summary LLM Response class: #{response.class}"
        puts "DEBUG: Simple Summary LLM Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: Simple Summary LLM Response sample: #{response.inspect[0..500]}"
      end
      
      parse_simple_summary_response(response, model)
    rescue => e
      { error: "Simple summary generation failed: #{e.message}" }
    end
  end
  
  private
  
  def build_comprehensive_analysis_prompt(low_reviews, high_reviews, keyword)
    # Limit reviews to avoid token limits
    limited_low_reviews = low_reviews.first(30)
    limited_high_reviews = high_reviews.first(30)
    
    low_reviews_text = limited_low_reviews.map do |review|
      content = review.content || ""
      content = content[0..200] + "..." if content.length > 200
      "App: #{review.app.name}\nRating: #{review.rating}/5\nTitle: #{review.title}\nReview: #{content}\n---"
    end.join("\n\n")
    
    high_reviews_text = limited_high_reviews.map do |review|
      content = review.content || ""
      content = content[0..200] + "..." if content.length > 200
      "App: #{review.app.name}\nRating: #{review.rating}/5\nTitle: #{review.title}\nReview: #{content}\n---"
    end.join("\n\n")
    
    <<~PROMPT
      Analyze the following reviews from the top apps for the keyword "#{keyword}". 
      
      You have two sets of reviews:
      1. LOW-RATING REVIEWS (1-2 stars): Dissatisfied users highlighting problems and missing features
      2. HIGH-RATING REVIEWS (4-5 stars): Satisfied users praising features they love
      
      Your task is to:
      
      1. From the HIGH-RATING reviews, identify "table stakes" features - the core features that users expect and praise across multiple apps. These are features any app in this category must have to be competitive.
      
      2. From the LOW-RATING reviews, identify pain points and opportunities for differentiation - problems that existing apps haven't solved well.
      
      3. Synthesize both to determine:
         - Top 3 "Table Stakes" features: What you need to fit in (baseline expectations)
         - Top 3 "Differentiators": What you need to stand out (unmet needs/opportunities)
      
      LOW-RATING REVIEWS (1-2 stars):
      
      #{low_reviews_text}
      
      HIGH-RATING REVIEWS (4-5 stars):
      
      #{high_reviews_text}
      
      Format your response as valid JSON with this structure:
      {
        "summary": "Brief executive summary of the competitive landscape",
        "table_stakes": [
          {
            "feature": "Feature name",
            "description": "Why this is essential",
            "evidence": "How often it appears in positive reviews"
          }
        ],
        "pain_points": [
          {
            "category": "Pain point category",
            "description": "What users are complaining about",
            "frequency": "How common this is"
          }
        ],
        "differentiators": [
          {
            "opportunity": "Opportunity name",
            "description": "How to stand out by addressing this",
            "rationale": "Why this would differentiate"
          }
        ],
        "competitive_summary": {
          "top_3_table_stakes": ["Feature 1", "Feature 2", "Feature 3"],
          "top_3_differentiators": ["Differentiator 1", "Differentiator 2", "Differentiator 3"]
        }
      }
    PROMPT
  end
  
  def build_analysis_prompt(reviews, keyword)
    # Limit reviews to avoid token limits
    limited_reviews = reviews.first(50)
    
    reviews_text = limited_reviews.map do |review|
      content = review.content || ""
      # Truncate long reviews
      content = content[0..200] + "..." if content.length > 200
      "App: #{review.app.name}\nRating: #{review.rating}/5\nTitle: #{review.title}\nReview: #{content}\n---"
    end.join("\n\n")
    
    <<~PROMPT
      Analyze the following 1-2 star reviews from the top apps for the keyword "#{keyword}". 
      
      These are negative reviews from users who are dissatisfied with these apps. Your task is to:
      
      1. Identify common patterns and pain points across these reviews
      2. Categorize the main complaints (e.g., UI/UX issues, performance problems, missing features, pricing concerns, etc.)
      3. Suggest specific opportunities for a new app that could address these shortcomings
      4. Prioritize the opportunities by potential impact and feasibility
      
      Reviews to analyze:
      
      #{reviews_text}
      
      Format your response as valid JSON with this structure:
      {
        "summary": "Brief executive summary",
        "patterns": [
          {
            "category": "Pain point category",
            "description": "What users are complaining about",
            "frequency": "How common this is"
          }
        ],
        "opportunities": [
          {
            "title": "Opportunity name",
            "description": "How to address this",
            "priority": "high/medium/low"
          }
        ]
      }
    PROMPT
  end
  
  def parse_analysis_response(response, review_count, model)
    # Handle OpenRouter response format
    content = if response.is_a?(String)
      # If response is already a string, use it directly
      response
    elsif response.is_a?(Hash)
      response.dig('choices', 0, 'message', 'content') || 
      response.dig(:choices, 0, :message, :content) ||
      response['message'] || 
      response[:message] ||
      response.to_s
    else
      response.to_s
    end
    
    puts "DEBUG: Extracted content (first 500 chars): #{content[0..500]}" if content && ENV['DEBUG']
    
    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if content.include?('```')
    
    # Try to extract JSON from the response
    json_match = content.match(/\{.*\}/m)
    
    if json_match
      begin
        analysis = JSON.parse(json_match[0])
        {
          llm_analysis: content,
          patterns: analysis['patterns'] || [],
          opportunities: analysis['opportunities'] || [],
          summary: analysis['summary'],
          total_reviews_analyzed: review_count,
          llm_model: model,
          raw_json: analysis  # Store the parsed JSON for easier access later
        }
      rescue JSON::ParserError
        # If JSON parsing fails, return the raw content
        {
          llm_analysis: content,
          patterns: [],
          opportunities: [],
          total_reviews_analyzed: review_count,
          llm_model: model
        }
      end
    else
      {
        llm_analysis: content,
        patterns: [],
        opportunities: [],
        total_reviews_analyzed: review_count,
        llm_model: model
      }
    end
  end
  
  def parse_comprehensive_analysis_response(response, low_review_count, high_review_count, model)
    # Handle OpenRouter response format
    content = if response.is_a?(String)
      response
    elsif response.is_a?(Hash)
      response.dig('choices', 0, 'message', 'content') || 
      response.dig(:choices, 0, :message, :content) ||
      response['message'] || 
      response[:message] ||
      response.to_s
    else
      response.to_s
    end
    
    puts "DEBUG: Extracted content (first 500 chars): #{content[0..500]}" if content && ENV['DEBUG']
    
    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if content.include?('```')
    
    # Try to extract JSON from the response
    json_match = content.match(/\{.*\}/m)
    
    if json_match
      begin
        analysis = JSON.parse(json_match[0])
        {
          llm_analysis: content,
          table_stakes: analysis['table_stakes'] || [],
          pain_points: analysis['pain_points'] || [],
          differentiators: analysis['differentiators'] || [],
          competitive_summary: analysis['competitive_summary'] || {},
          summary: analysis['summary'],
          total_low_reviews_analyzed: low_review_count,
          total_high_reviews_analyzed: high_review_count,
          llm_model: model,
          raw_json: analysis
        }
      rescue JSON::ParserError
        {
          llm_analysis: content,
          table_stakes: [],
          pain_points: [],
          differentiators: [],
          competitive_summary: {},
          total_low_reviews_analyzed: low_review_count,
          total_high_reviews_analyzed: high_review_count,
          llm_model: model
        }
      end
    else
      {
        llm_analysis: content,
        table_stakes: [],
        pain_points: [],
        differentiators: [],
        competitive_summary: {},
        total_low_reviews_analyzed: low_review_count,
        total_high_reviews_analyzed: high_review_count,
        llm_model: model
      }
    end
  end
  
  def parse_simple_summary_response(response, model)
    # Handle OpenRouter response format
    content = if response.is_a?(String)
      response
    elsif response.is_a?(Hash)
      response.dig('choices', 0, 'message', 'content') || 
      response.dig(:choices, 0, :message, :content) ||
      response['message'] || 
      response[:message] ||
      response.to_s
    else
      response.to_s
    end
    
    puts "DEBUG: Simple Summary Content (first 500 chars): #{content[0..500]}" if content && ENV['DEBUG']
    
    # For simple summary, we just return the content as-is since it should be plain text
    {
      summary: content&.strip,
      llm_model: model
    }
  end
end