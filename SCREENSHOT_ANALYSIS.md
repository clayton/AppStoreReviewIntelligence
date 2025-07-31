# Screenshot Analysis Feature

This feature analyzes App Store screenshots for the top 10 apps using Google's Gemini 2.5 Pro model via OpenRouter.

## Setup

1. Ensure you have an OpenRouter API key set as an environment variable:
   ```bash
   export OPENROUTER_API_KEY="your-openrouter-api-key"
   ```
   
   This uses the same API key and connectivity as the review analysis script.

2. Make sure the database is migrated:
   ```bash
   bundle exec rake db:migrate
   ```

## Usage

Analyze screenshots for apps matching a keyword:
```bash
./analyze_screenshots.rb analyze "meditation"
```

Options:
- `--limit N` - Number of top apps to analyze (default: 10)
- `--country CODE` - App Store country code (default: 'us')
- `--force` - Force fresh analysis even if cached results exist

View analysis history for a keyword:
```bash
./analyze_screenshots.rb history "meditation"
```

Show help:
```bash
./analyze_screenshots.rb help
```

## What it does

The script follows this workflow:

1. **App Discovery**: 
   - Searches for top apps matching your keyword
   - Reuses cached app lists if less than 2 days old
   - Otherwise fetches fresh data from App Store

2. **Screenshot Analysis**:
   - Checks for existing analyses (cached for 7 days)
   - If no cache, fetches screenshots from iTunes API
   - Analyzes them using Gemini 2.5 Pro via OpenRouter
   - Saves results to database

3. **Intelligent Caching**:
   - App lists are cached for 2 days
   - Screenshot analyses are cached for 7 days
   - Use `--force` to bypass cache

The analysis includes:
- Description of each screenshot in order
- Keywords and text used across screenshots
- Visual style and design patterns
- Content themes and messaging
- Target audience insights

## Model Used

The script uses `google/gemini-2.5-pro` via OpenRouter API, the same as the review analysis script. This ensures consistency in API usage and billing across both features.

## Database Schema

Screenshot analyses are stored in the `screenshot_analyses` table with:
- `app_id` - Reference to the app
- `screenshot_count` - Number of screenshots analyzed
- `analysis` - Full text analysis from Gemini
- `screenshot_urls` - JSON array of screenshot URLs
- `created_at` / `updated_at` - Timestamps

## Files Created

- `lib/app_screenshots.rb` - Fetches app details and screenshots from iTunes API
- `lib/screenshot_analyzer.rb` - Handles OpenRouter API integration for screenshot analysis using Gemini 2.5 Pro
- `models/screenshot_analysis.rb` - ActiveRecord model
- `analyze_screenshots.rb` - Main script to run the analysis