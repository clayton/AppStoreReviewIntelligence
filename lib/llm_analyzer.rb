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
  
  private
  
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
end