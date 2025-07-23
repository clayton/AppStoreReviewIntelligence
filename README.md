# App Store Review Intelligence

A Ruby tool that analyzes negative reviews from top App Store apps to identify market opportunities and pain points.

## Features

- Searches iTunes App Store for top apps by keyword
- Fetches and filters 1-2 star reviews from the RSS feed
- Stores data in SQLite for caching and historical analysis
- Uses OpenRouter AI to analyze patterns and identify opportunities
- Command-line interface with multiple commands

## Setup

1. Install dependencies:
```bash
bundle install
```

2. Set up your OpenRouter API key:
```bash
cp .env.example .env
# Edit .env and add your OPENROUTER_API_KEY
```

3. Set up the database:
```bash
bundle exec rake db:create
bundle exec rake db:migrate
```

## Usage

### Analyze reviews for a keyword

```bash
./app_store_review_intelligence.rb analyze "fitness"
```

Options:
- `--limit=10` - Number of top apps to analyze (default: 10)
- `--country=us` - App Store country code (default: us)
- `--model=google/gemini-2.0-flash-exp:free` - OpenRouter model to use
- `--force` - Force fresh fetch of reviews (ignore cache)

### View analysis history

```bash
./app_store_review_intelligence.rb history "fitness"
```

### Show details of a specific analysis

```bash
./app_store_review_intelligence.rb show 1
```

### List cached apps for a keyword

```bash
./app_store_review_intelligence.rb apps "fitness"
```

## How it works

1. **Search**: Uses iTunes Search API to find top apps for your keyword
2. **Fetch Reviews**: Uses the RSS feed to get recent customer reviews
3. **Filter**: Extracts only 1-2 star reviews (negative feedback)
4. **Cache**: Stores apps and reviews in SQLite to avoid redundant API calls
5. **Analyze**: Sends aggregated reviews to AI for pattern analysis
6. **Report**: Displays patterns, pain points, and opportunities

## Database Schema

- **apps**: Stores app metadata from search results
- **reviews**: Stores individual reviews with ratings
- **analyses**: Stores AI analysis results

## Notes

- Reviews are cached for 24 hours to reduce API calls
- The RSS feed only provides the most recent ~500 reviews per app
- Rate limiting is implemented with 1-second delays between requests
- All data is stored locally in SQLite

## Example Output

```
🔍 App Store Review Intelligence
==================================================

📊 Summary:
- Found 10 apps
- Collected 127 negative reviews

🤖 Analyzing reviews with AI...

✨ Analysis Results
==================================================

📝 Summary:
Users are frustrated with subscription pricing, lack of offline features...

🔍 Common Patterns:
1. Pricing Issues
   Users feel subscription costs are too high for basic features
   Frequency: Very Common
   Examples:
   - "$10/month is ridiculous for basic workout tracking..."
   - "Why do I need to pay monthly just to log my exercises..."

💡 Opportunities:
1. One-time purchase option (Priority: high)
   Offer a lifetime license as an alternative to subscriptions
   Implementation: Create a premium tier with one-time payment

==================================================
Reviews analyzed: 127
Model used: google/gemini-2.0-flash-exp:free
```