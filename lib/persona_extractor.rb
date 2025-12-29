class PersonaExtractor
  # Patterns to match self-identifying phrases in reviews
  PERSONA_PATTERNS = [
    # "As a ___" patterns (most common)
    /\bas\s+a\s+([^,.!?]{3,50}?)(?=[,.!?]|\s+(?:I|i|who|and|this|the|it))/i,

    # "I'm a ___" / "I am a ___" patterns
    /\bi(?:'m|'m|\s+am)\s+a\s+([^,.!?]{3,50}?)(?=[,.!?]|\s+(?:and|who|so|that|this))/i,

    # "Being a ___" patterns
    /\bbeing\s+a\s+([^,.!?]{3,50}?)(?=[,.!?]|\s+(?:I|i|this|and|it))/i,

    # "As someone who ___" patterns
    /\bas\s+someone\s+who\s+([^,.!?]{5,60}?)(?=[,.!?])/i,
  ]

  # Common false positives to exclude
  EXCLUSIONS = [
    /^result/i,
    /^matter\s+of/i,
    /^whole/i,
    /^way\s+to/i,
    /^bonus/i,
    /^gift/i,
    /^treat/i,
    /^surprise/i,
    /^reminder/i,
    /^reference/i,
    /^starting\s+point/i,
    /^test/i,
    /^trial/i,
    /^backup/i,
    /^replacement/i,
    /^default/i,
    /^last\s+resort/i,
    /^first\s+step/i,
    /^side\s+effect/i,
    /^consequence/i,
  ]

  def initialize
    @matches = {}
  end

  # Extract personas from an array of Review objects
  # Returns hash with raw_matches and total_reviews_with_personas
  def extract_from_reviews(reviews)
    @matches = {}
    reviews_with_matches = 0

    reviews.each do |review|
      content = review.respond_to?(:content) ? review.content : review[:content]
      title = review.respond_to?(:title) ? review.title : review[:title]
      review_id = review.respond_to?(:id) ? review.id : review[:review_id]

      # Search both title and content
      text_to_search = [title, content].compact.join(" ")

      found_in_review = false

      PERSONA_PATTERNS.each do |pattern|
        text_to_search.scan(pattern) do |match|
          phrase = match[0].strip.downcase

          # Skip if it matches an exclusion pattern
          next if EXCLUSIONS.any? { |exclusion| phrase =~ exclusion }

          # Skip very short matches (likely noise)
          next if phrase.length < 3

          # Skip if it's just articles or common words
          next if phrase =~ /^(the|a|an|very|really|just|only|also)\s*$/i

          found_in_review = true

          if @matches[phrase]
            @matches[phrase][:count] += 1
            @matches[phrase][:review_ids] << review_id unless @matches[phrase][:review_ids].include?(review_id)
          else
            @matches[phrase] = {
              phrase: phrase,
              count: 1,
              review_ids: [review_id]
            }
          end
        end
      end

      reviews_with_matches += 1 if found_in_review
    end

    # Sort by count descending and convert to array
    raw_matches = @matches.values.sort_by { |m| -m[:count] }

    {
      raw_matches: raw_matches,
      total_reviews_with_personas: reviews_with_matches
    }
  end

  # Extract from raw text strings (useful for testing)
  def extract_from_text(text)
    matches = []

    PERSONA_PATTERNS.each do |pattern|
      text.scan(pattern) do |match|
        phrase = match[0].strip.downcase

        next if EXCLUSIONS.any? { |exclusion| phrase =~ exclusion }
        next if phrase.length < 3
        next if phrase =~ /^(the|a|an|very|really|just|only|also)\s*$/i

        matches << phrase
      end
    end

    matches.uniq
  end
end
