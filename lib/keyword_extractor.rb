require 'open_router'
require 'json'

class KeywordExtractor
  DEFAULT_MODEL = 'google/gemini-3-flash-preview'

  def initialize
    @client = OpenRouter::Client.new(access_token: ENV['OPENROUTER_API_KEY'])
  end

  def extract(apps_metadata, keyword, model = DEFAULT_MODEL)
    return { error: "No app metadata to analyze" } if apps_metadata.empty?

    prompt = build_keyword_prompt(apps_metadata, keyword)

    begin
      messages = [
        {
          role: "system",
          content: "You are an expert App Store Optimization (ASO) keyword researcher with deep knowledge of Apple's App Store search algorithm, keyword weighting, and competitive keyword intelligence."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      response = @client.complete(messages,
        model: model,
        extras: { temperature: 0.5 }
      )

      if ENV['DEBUG']
        puts "\nDEBUG: Keyword Extraction Response class: #{response.class}"
        puts "DEBUG: Keyword Extraction Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: Keyword Extraction Response sample: #{response.inspect[0..500]}"
      end

      parse_keyword_response(response, apps_metadata.length, model)
    rescue => e
      { error: "Keyword extraction failed: #{e.message}" }
    end
  end

  private

  def build_keyword_prompt(apps_metadata, keyword)
    apps_text = apps_metadata.map.with_index do |app, i|
      <<~APP
        #{i + 1}. #{app[:name]} (Rank ##{app[:rank]})
           Subtitle: #{app[:subtitle] || 'Not available'}
           Rating: #{app[:rating]}/5 (#{app[:rating_count]} reviews)
           Description (first 500 chars): #{truncate(app[:description], 500)}
      APP
    end.join("\n")

    <<~PROMPT
      Analyze the following competitor app metadata from the App Store search results for "#{keyword}" and extract keyword intelligence.

      COMPETITOR APPS (ranked by App Store search):
      #{apps_text}

      Your task:

      1. **High-frequency keywords**: Identify terms that appear across many competitors' titles, subtitles, and descriptions. These are "table stakes" keywords that signal relevance for this category.

      2. **Title keywords**: Extract the exact meaningful terms each competitor puts in their app name (excluding common words like "the", "app", "-", etc.).

      3. **Subtitle keywords**: Extract terms from subtitles. These are heavily weighted by Apple's search algorithm.

      4. **Description keywords**: Identify repeated terms in the first few sentences of descriptions across competitors.

      5. **Keyword gaps/opportunities**: Terms that only 1-2 competitors use. These represent lower-competition keyword opportunities.

      6. **Suggested keyword field**: Create a prioritized, comma-separated list of keywords optimized for the App Store Connect 100-character keyword field. Do NOT include the app name or category name (Apple ignores duplicates). Focus on high-value terms not already covered by a title or subtitle.

      Format your response as valid JSON:
      {
        "high_frequency_keywords": [
          {
            "keyword": "term",
            "competitor_count": 7,
            "total_competitors": 10,
            "found_in": ["App Name 1", "App Name 2"]
          }
        ],
        "title_keywords": [
          {
            "app_name": "App Name",
            "keywords": ["keyword1", "keyword2"]
          }
        ],
        "subtitle_keywords": [
          {
            "app_name": "App Name",
            "subtitle": "The full subtitle text",
            "keywords": ["keyword1", "keyword2"]
          }
        ],
        "description_keywords": [
          {
            "keyword": "term",
            "competitor_count": 5,
            "context": "Brief note on how it's used"
          }
        ],
        "keyword_gaps": [
          {
            "keyword": "term",
            "used_by_count": 1,
            "used_by": ["App Name"],
            "opportunity_note": "Why this is an opportunity"
          }
        ],
        "suggested_keyword_field": {
          "keywords": "comma,separated,keywords,max,100,chars",
          "character_count": 42,
          "rationale": "Brief explanation of prioritization"
        }
      }

      IMPORTANT:
      - Only extract real keywords found in the provided metadata
      - The suggested keyword field MUST be 100 characters or fewer
      - Sort high-frequency keywords by competitor_count descending
      - Sort keyword gaps by opportunity (fewest competitors first)
      - Be specific and actionable
    PROMPT
  end

  def truncate(text, length)
    return '' if text.nil?
    text.length > length ? text[0...length] + '...' : text
  end

  def parse_keyword_response(response, app_count, model)
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

    puts "DEBUG: Extracted keyword content (first 500 chars): #{content[0..500]}" if content && ENV['DEBUG']

    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '') if content.include?('```')

    json_match = content.match(/\{.*\}/m)

    if json_match
      begin
        parsed = JSON.parse(json_match[0])
        {
          llm_analysis: content,
          high_frequency_keywords: parsed['high_frequency_keywords'] || [],
          title_keywords: parsed['title_keywords'] || [],
          subtitle_keywords: parsed['subtitle_keywords'] || [],
          description_keywords: parsed['description_keywords'] || [],
          keyword_gaps: parsed['keyword_gaps'] || [],
          suggested_keyword_field: parsed['suggested_keyword_field'] || {},
          app_count: app_count,
          llm_model: model
        }
      rescue JSON::ParserError
        {
          llm_analysis: content,
          high_frequency_keywords: [],
          title_keywords: [],
          subtitle_keywords: [],
          description_keywords: [],
          keyword_gaps: [],
          suggested_keyword_field: {},
          app_count: app_count,
          llm_model: model,
          parse_warning: "Failed to parse JSON keyword analysis"
        }
      end
    else
      {
        llm_analysis: content,
        high_frequency_keywords: [],
        title_keywords: [],
        subtitle_keywords: [],
        description_keywords: [],
        keyword_gaps: [],
        suggested_keyword_field: {},
        app_count: app_count,
        llm_model: model
      }
    end
  end
end
