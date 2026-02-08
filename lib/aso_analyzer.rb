require 'open_router'
require 'json'

class AsoAnalyzer
  DEFAULT_MODEL = 'google/gemini-3-flash-preview'

  def initialize
    @client = OpenRouter::Client.new(access_token: ENV['OPENROUTER_API_KEY'])
  end

  def analyze(user_app_metadata, competitor_apps_metadata, keyword, model = DEFAULT_MODEL)
    return { error: "No competitor data to analyze" } if competitor_apps_metadata.empty?

    prompt = build_aso_prompt(user_app_metadata, competitor_apps_metadata, keyword)

    begin
      messages = [
        {
          role: "system",
          content: "You are an expert App Store Optimization (ASO) consultant with deep knowledge of keyword optimization, competitive positioning, and conversion rate optimization for mobile apps."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      response = @client.complete(messages,
        model: model,
        extras: { temperature: 0.7 }
      )

      if ENV['DEBUG']
        puts "\nDEBUG: ASO Response class: #{response.class}"
        puts "DEBUG: ASO Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: ASO Response sample: #{response.inspect[0..500]}"
      end

      parse_aso_response(response, competitor_apps_metadata.length, model)
    rescue => e
      { error: "ASO analysis failed: #{e.message}" }
    end
  end

  private

  def build_aso_prompt(user_app, competitors, keyword)
    competitors_text = competitors.map.with_index do |comp, i|
      <<~COMPETITOR
        #{i + 1}. #{comp[:name]} (Rank ##{comp[:rank]})
           Subtitle: #{comp[:subtitle] || 'Not available'}
           Category: #{comp[:category] || 'N/A'}
           Rating: #{comp[:rating]}/5 (#{comp[:rating_count]} reviews)
           Description (first 300 chars): #{truncate(comp[:description], 300)}
      COMPETITOR
    end.join("\n")

    <<~PROMPT
      Analyze the following app metadata and provide ASO recommendations to improve discoverability and conversion for the keyword "#{keyword}".

      YOUR APP TO OPTIMIZE:
      - Name: #{user_app[:name]}
      - Current Subtitle: #{user_app[:subtitle] || 'None set'}
      - Current Promotional Text: #{user_app[:promotional_text] || 'None set'}
      - Category: #{user_app[:category] || 'N/A'}
      - Rating: #{user_app[:rating]}/5 (#{user_app[:rating_count]} reviews)
      - Description (first 500 chars): #{truncate(user_app[:description], 500)}

      COMPETITOR APPS (ranked by App Store search for "#{keyword}"):
      #{competitors_text}

      Provide specific, actionable ASO recommendations. Format as valid JSON:
      {
        "name_recommendations": {
          "current_analysis": "Analysis of current name effectiveness for the keyword",
          "suggestions": ["suggestion 1", "suggestion 2"],
          "keywords_to_include": ["keyword1", "keyword2"]
        },
        "subtitle_recommendations": {
          "current_analysis": "Analysis of current subtitle or lack thereof",
          "suggested_subtitles": ["30-char option 1", "30-char option 2", "30-char option 3"],
          "competitor_patterns": "What successful competitors are doing"
        },
        "promotional_text_recommendations": {
          "current_analysis": "Analysis of promotional text effectiveness",
          "suggested_text": "Full 170-character promotional text suggestion",
          "key_themes": ["theme1", "theme2"]
        },
        "keyword_recommendations": {
          "primary_keywords": ["high-priority keyword 1", "keyword 2"],
          "secondary_keywords": ["lower-priority keywords"],
          "competitor_keywords": ["keywords competitors use effectively"],
          "gap_keywords": ["keywords competitors miss that you could target"]
        },
        "description_recommendations": {
          "current_analysis": "Analysis of description effectiveness",
          "suggested_opening": "Strong first paragraph suggestion (most important for ASO)",
          "key_features_to_highlight": ["feature1", "feature2"],
          "keyword_placement_tips": "Where to place keywords naturally"
        },
        "competitive_summary": {
          "your_current_position": "Assessment of where you stand",
          "top_3_priorities": ["Most impactful change 1", "Change 2", "Change 3"],
          "unique_angles": ["Positioning opportunities competitors don't own"]
        }
      }

      IMPORTANT:
      - Subtitles MUST be under 30 characters
      - Promotional text MUST be under 170 characters
      - Base suggestions on gaps you see vs competitors
      - Be specific and actionable
    PROMPT
  end

  def truncate(text, length)
    return '' if text.nil?
    text.length > length ? text[0...length] + '...' : text
  end

  def parse_aso_response(response, competitor_count, model)
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

    puts "DEBUG: Extracted ASO content (first 500 chars): #{content[0..500]}" if content && ENV['DEBUG']

    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if content.include?('```')

    # Try to extract JSON from the response
    json_match = content.match(/\{.*\}/m)

    if json_match
      begin
        recommendations = JSON.parse(json_match[0])
        {
          llm_analysis: content,
          recommendations: recommendations,
          competitor_count: competitor_count,
          llm_model: model
        }
      rescue JSON::ParserError
        {
          llm_analysis: content,
          recommendations: {},
          competitor_count: competitor_count,
          llm_model: model,
          parse_warning: "Failed to parse JSON recommendations"
        }
      end
    else
      {
        llm_analysis: content,
        recommendations: {},
        competitor_count: competitor_count,
        llm_model: model
      }
    end
  end
end
