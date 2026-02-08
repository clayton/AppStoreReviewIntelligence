require 'open_router'
require 'json'
require 'base64'
require 'httparty'

class ScreenshotAnalyzer
  DEFAULT_MODEL = 'google/gemini-3-flash-preview'
  
  def initialize
    @client = OpenRouter::Client.new(
      access_token: ENV['OPENROUTER_API_KEY']
    )
  end
  
  def analyze_screenshots(app_name, screenshot_urls, model = DEFAULT_MODEL)
    return nil if screenshot_urls.empty?
    
    # Download all screenshots
    screenshots_data = []
    screenshot_urls.each_with_index do |url, index|
      puts "Downloading screenshot #{index + 1} of #{screenshot_urls.length}..."
      response = HTTParty.get(url)
      
      if response.success?
        screenshots_data << {
          index: index + 1,
          url: url,
          data: Base64.strict_encode64(response.body),
          mime_type: "image/png"
        }
      else
        puts "Failed to download screenshot from #{url}"
      end
    end
    
    return nil if screenshots_data.empty?
    
    # Build the message content with images
    content_parts = [
      {
        type: "text",
        text: "You are analyzing App Store screenshots for the app '#{app_name}'. Please provide:\n\n1. A description of each screenshot in order (what is shown, key features highlighted)\n2. An overall analysis of:\n   - Keywords and text used across screenshots\n   - Visual style and design patterns\n   - Content themes and messaging\n   - Target audience insights based on the screenshots\n\nBe specific and detailed in your analysis."
      }
    ]
    
    # Add each screenshot as an image part
    screenshots_data.each do |screenshot|
      content_parts << {
        type: "text",
        text: "\nScreenshot #{screenshot[:index]}:"
      }
      content_parts << {
        type: "image_url",
        image_url: {
          url: "data:#{screenshot[:mime_type]};base64,#{screenshot[:data]}"
        }
      }
    end
    
    messages = [
      {
        role: "system",
        content: "You are an expert UI/UX analyst specializing in mobile app design and App Store optimization."
      },
      {
        role: "user",
        content: content_parts
      }
    ]
    
    begin
      response = @client.complete(messages, 
        model: model,
        extras: {
          temperature: 0.7
        }
      )
      
      if ENV['DEBUG']
        puts "\nDEBUG: Screenshot Analysis Response class: #{response.class}"
        puts "DEBUG: Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: Response sample: #{response.inspect[0..500]}"
      end
      
      # Extract the analysis text from the response
      analysis_text = if response.is_a?(String)
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
      
      {
        app_name: app_name,
        screenshot_count: screenshots_data.length,
        analysis: analysis_text,
        screenshot_urls: screenshot_urls,
        llm_model: model
      }
    rescue => e
      puts "Error calling OpenRouter API: #{e.message}"
      puts e.backtrace.first(3) if ENV['DEBUG']
      nil
    end
  end

  def load_local_screenshots(folder_path)
    extensions = %w[.png .jpg .jpeg .PNG .JPG .JPEG]

    image_files = Dir.glob(File.join(folder_path, "*")).select do |file|
      File.file?(file) && extensions.any? { |ext| file.end_with?(ext) }
    end.sort

    screenshots_data = []
    image_files.each_with_index do |file_path, index|
      puts "Loading local screenshot #{index + 1}: #{File.basename(file_path)}"
      data = File.binread(file_path)
      mime_type = file_path.downcase.end_with?('.png') ? 'image/png' : 'image/jpeg'

      screenshots_data << {
        index: index + 1,
        path: file_path,
        data: Base64.strict_encode64(data),
        mime_type: mime_type
      }
    end

    screenshots_data
  end

  def download_screenshots(screenshot_urls)
    screenshots_data = []
    screenshot_urls.each_with_index do |url, index|
      puts "Downloading screenshot #{index + 1} of #{screenshot_urls.length}..."
      response = HTTParty.get(url)

      if response.success?
        screenshots_data << {
          index: index + 1,
          url: url,
          data: Base64.strict_encode64(response.body),
          mime_type: "image/png"
        }
      else
        puts "Failed to download screenshot from #{url}"
      end
    end
    screenshots_data
  end

  def compare_screenshots(competitor_name, competitor_urls, local_screenshots, model = DEFAULT_MODEL)
    return nil if competitor_urls.empty? || local_screenshots.empty?

    # Download competitor screenshots
    puts "\nDownloading competitor screenshots..."
    competitor_data = download_screenshots(competitor_urls)
    return nil if competitor_data.empty?

    compare_local_screenshots(competitor_name, competitor_data, local_screenshots, model)
  end

  def compare_local_screenshots(competitor_name, competitor_screenshots, local_screenshots, model = DEFAULT_MODEL)
    return nil if competitor_screenshots.empty? || local_screenshots.empty?

    # Build the message content with both sets of images
    content_parts = [
      {
        type: "text",
        text: build_comparison_prompt(competitor_name, competitor_screenshots.length, local_screenshots.length)
      }
    ]

    # Add competitor screenshots
    competitor_screenshots.each do |screenshot|
      content_parts << {
        type: "text",
        text: "\nCOMPETITOR Screenshot #{screenshot[:index]}:"
      }
      content_parts << {
        type: "image_url",
        image_url: {
          url: "data:#{screenshot[:mime_type]};base64,#{screenshot[:data]}"
        }
      }
    end

    # Add local screenshots
    local_screenshots.each do |screenshot|
      content_parts << {
        type: "text",
        text: "\nYOUR Screenshot #{screenshot[:index]}:"
      }
      content_parts << {
        type: "image_url",
        image_url: {
          url: "data:#{screenshot[:mime_type]};base64,#{screenshot[:data]}"
        }
      }
    end

    messages = [
      {
        role: "system",
        content: "You are an expert App Store Optimization (ASO) consultant and UI/UX designer specializing in mobile app screenshots and conversion optimization."
      },
      {
        role: "user",
        content: content_parts
      }
    ]

    begin
      puts "\nAnalyzing and comparing screenshots..."
      response = @client.complete(messages,
        model: model,
        extras: {
          temperature: 0.7
        }
      )

      if ENV['DEBUG']
        puts "\nDEBUG: Comparison Response class: #{response.class}"
        puts "DEBUG: Response keys: #{response.keys rescue 'N/A'}"
        puts "DEBUG: Response sample: #{response.inspect[0..500]}"
      end

      analysis_text = if response.is_a?(String)
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

      {
        competitor_name: competitor_name,
        competitor_screenshot_count: competitor_screenshots.length,
        local_screenshot_count: local_screenshots.length,
        analysis: analysis_text,
        llm_model: model
      }
    rescue => e
      puts "Error calling OpenRouter API: #{e.message}"
      puts e.backtrace.first(3) if ENV['DEBUG']
      nil
    end
  end

  private

  def build_comparison_prompt(competitor_name, competitor_count, local_count)
    <<~PROMPT
      You are analyzing and comparing two sets of App Store screenshots.

      COMPETITOR APP: #{competitor_name}
      The competitor has #{competitor_count} screenshots, labeled as "COMPETITOR Screenshot 1", "COMPETITOR Screenshot 2", etc.

      YOUR APP:
      You have #{local_count} screenshots, labeled as "YOUR Screenshot 1", "YOUR Screenshot 2", etc.

      Please provide a detailed analysis:

      ## 1. COMPETITOR SCREENSHOT FLOW ANALYSIS
      Describe the competitor's screenshot journey:
      - What is the overall narrative/story?
      - How do the screenshots progress (onboarding, key features, social proof)?
      - What key features are highlighted in each screenshot?
      - What value propositions are communicated?
      - What design patterns and visual techniques are used?

      ## 2. YOUR SCREENSHOT ANALYSIS
      Describe your current screenshot flow:
      - What story do your screenshots tell?
      - What features are highlighted?
      - How clear is the value proposition?

      ## 3. GAP ANALYSIS
      Compare your screenshots to the competitor's:
      - What is the competitor doing that you are NOT doing?
      - What messaging or features are you missing?
      - Where are you weaker in visual presentation?

      ## 4. SPECIFIC IMPROVEMENT RECOMMENDATIONS
      Provide actionable, specific improvements for EACH of your screenshots:

      For each screenshot, tell me:
      - **Screenshot [N]**: Current state description
      - **Problem**: What is wrong or could be better
      - **Recommendation**: Specific change to make
      - **Priority**: High/Medium/Low

      ## 5. NEW SCREENSHOTS TO CREATE
      Based on the competitor analysis, recommend any entirely new screenshots you should create that you currently do not have.

      ## 6. RECOMMENDED SCREENSHOT ORDER
      Suggest the optimal order for your screenshots based on best practices and the competitor's approach.

      Be specific and actionable. Reference specific visual elements, copy text, and design patterns.
    PROMPT
  end
end