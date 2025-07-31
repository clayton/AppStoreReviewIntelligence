require 'open_router'
require 'json'
require 'base64'
require 'httparty'

class ScreenshotAnalyzer
  DEFAULT_MODEL = 'google/gemini-2.5-pro'
  
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
end