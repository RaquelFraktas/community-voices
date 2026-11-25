module Themes
  LABELERS = %w[llm tfidf].freeze

  # Names clusters with the chat model, falling back to title terms. Tests and THEME_LABELER=tfidf use
  # title terms only.
  def self.labeler(name = ENV.fetch("THEME_LABELER", "llm"))
    raise ArgumentError, "THEME_LABELER must be one of #{LABELERS.join(', ')}, got #{name.inspect}" unless LABELERS.include?(name)

    Rails.env.test? || name == "tfidf" ? Labeler.new : LlmLabeler.new
  end
end
