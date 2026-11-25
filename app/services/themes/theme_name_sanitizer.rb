module Themes
  # Turns a chat model's reply into a short theme name, or nil when the reply is not usable as one: empty,
  # a refusal, a full sentence, or a document such as a Markdown heading.
  class ThemeNameSanitizer
    MAX_WORDS = 4
    MAX_LENGTH = 40
    MAX_REPLY_WORDS = 8
    LEADING_NOISE = /\A(?:[-*•]\s+|\d+[.)]\s+|(?:theme(?:\s+name)?|name|label)\s*:\s*)+/i
    QUOTES_AND_MARKUP = /["“”‘’'`*_]/
    REFUSAL = /\A(?:i\b|i'm\b|sorry\b|as an\b|here is\b|here's\b|sure\b)/i

    def sanitize(reply)
      line = reply.to_s.lines.map(&:strip).find(&:present?)
      return if line.nil? || line.start_with?("#") || line.match?(REFUSAL)

      name = line.sub(LEADING_NOISE, "").gsub(QUOTES_AND_MARKUP, "").sub(/[.:;!?,]+\z/, "").squish
      return unless usable?(name)

      limit(name)
    end

    private

    def usable?(name)
      name.match?(/[[:alpha:]]/) && name.split.size <= MAX_REPLY_WORDS
    end

    def limit(name)
      name.split.first(MAX_WORDS).each_with_object(+"") do |word, limited|
        candidate = limited.empty? ? word : "#{limited} #{word}"
        break limited if candidate.length > MAX_LENGTH

        limited.replace(candidate)
      end.presence
    end
  end
end
