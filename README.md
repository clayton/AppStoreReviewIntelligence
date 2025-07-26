# App Store Review Intelligence

Analyze negative reviews from App Store apps to identify opportunities and common pain points.

## Setup

1. Install dependencies:
   ```bash
   bundle install
   rake db:migrate
   ```

2. Create a `.env` file with your OpenRouter API key:
   ```bash
   echo "OPENROUTER_API_KEY=your_key_here" > .env
   ```

## Usage

Analyze top apps for a keyword:
```bash
ruby app_store_review_intelligence.rb analyze "photo editor"
```

View analysis history:
```bash
ruby app_store_review_intelligence.rb history "photo editor"
```

## What it does

This tool:
- Searches the App Store for top apps matching your keyword
- Collects negative reviews (1-3 stars) from those apps
- Uses AI to identify common patterns and opportunities
- Caches results to avoid redundant API calls