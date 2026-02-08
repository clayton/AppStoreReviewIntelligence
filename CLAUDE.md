# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

App Store Review Intelligence - A Ruby application that analyzes App Store reviews to identify opportunities and common pain points. The tool searches for top apps, collects their reviews, and uses AI to identify patterns, table stakes features, and differentiation opportunities.

## Common Development Commands

### Setup and Dependencies
```bash
bundle install                # Install Ruby dependencies
bundle exec rake db:migrate   # Run database migrations
```

### Running the Application
```bash
# Main review analysis tool
./app_store_review_intelligence.rb analyze "keyword"           # Analyze reviews for apps matching keyword
./app_store_review_intelligence.rb analyze "keyword" --limit=5 # Analyze top 5 apps
./app_store_review_intelligence.rb history "keyword"           # View analysis history
./app_store_review_intelligence.rb apps "keyword"              # List cached apps

# Screenshot analysis tool  
./analyze_screenshots.rb analyze "keyword"                     # Analyze screenshots for apps
./analyze_screenshots.rb history "keyword"                     # View screenshot analysis history

# Debug mode
DEBUG=1 ./app_store_review_intelligence.rb analyze "keyword"   # Run with debug output
```

### Environment Variables
Create a `.env` file with:
```
OPENROUTER_API_KEY=your_key_here
```

## Architecture

### Core Components

1. **CLI Interface** (`app_store_review_intelligence.rb`)
   - Thor-based CLI handling user commands
   - Orchestrates the review aggregation and analysis pipeline
   - Manages caching logic (3-day cache for analyses, review count change detection)

2. **Data Collection Layer** (`lib/`)
   - `AppStoreSearch`: Searches iTunes API for top apps by keyword
   - `AppStoreReviews`: Fetches app reviews from iTunes RSS feeds
   - `ReviewAggregator`: Coordinates fetching and caching of reviews across multiple apps
   - `AppScreenshots`: Fetches app screenshots from iTunes API

3. **AI Analysis** (`lib/`)
   - `LLMAnalyzer`: Sends reviews to OpenRouter API (Gemini 2.5 Pro by default)
   - Performs comprehensive analysis identifying table stakes, pain points, and differentiators
   - `ScreenshotAnalyzer`: Analyzes app screenshots using vision models

4. **Data Models** (`models/`)
   - `App`: Stores app metadata with keyword association
   - `Review`: Individual reviews with ratings and content  
   - `Analysis`: Cached AI analysis results
   - `ScreenshotAnalysis`: Cached screenshot analysis results

### Key Design Patterns

- **Intelligent Caching**: Apps and reviews are cached in SQLite to minimize API calls. Reviews refresh after 3 days, analyses cache based on review count changes.
- **Comprehensive Analysis**: Analyzes both low-rating (1-2 stars) and high-rating (4-5 stars) reviews to identify table stakes features vs differentiation opportunities.
- **Structured Output**: AI responses are parsed as JSON for consistent data structure with fallback handling for malformed responses.

## Database

SQLite database at `db/app_store_reviews.sqlite3` with tables:
- `apps`: App metadata and search rankings
- `reviews`: Individual review content and ratings
- `analyses`: AI analysis results with patterns and opportunities
- `screenshot_analyses`: Screenshot analysis results

## External Dependencies

- **iTunes Search API**: For finding apps by keyword
- **iTunes RSS Feed API**: For fetching app reviews
- **OpenRouter API**: For LLM analysis (requires API key)
- **Gemini 2.5 Pro**: Default model for analysis via OpenRouter