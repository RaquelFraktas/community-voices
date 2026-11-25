module Themes
  # Asks the chat model for a short, readable name for each cluster, from the titles and snippets of the
  # chunks closest to its centroid. Falls back to the title-term label when the model is unavailable, replies
  # with something that is not a name, or repeats a name already given to another cluster.
  class LlmLabeler
    SYSTEM_PROMPT = "You name discussion themes for a newsletter about the Ruby on Rails forum. " \
                    "Reply with the theme name only.".freeze

    def initialize(chat_client: Llm.client, fallback: Labeler.new, sanitizer: ThemeNameSanitizer.new)
      @chat_client = chat_client
      @fallback = fallback
      @sanitizer = sanitizer
    end

    def label(descriptions, all_titles:)
      fallback_labels = @fallback.label(descriptions, all_titles: all_titles)
      taken = Set.new
      descriptions.to_h do |cluster, description|
        name = model_name_for(description)
        label = name && !taken.include?(name.downcase) ? name : fallback_labels.fetch(cluster)
        taken << label.downcase
        [ cluster, label ]
      end
    end

    private

    def model_name_for(description)
      return if @model_unavailable

      @sanitizer.sanitize(@chat_client.complete(system: SYSTEM_PROMPT, user: prompt_for(description)))
    rescue Llm::UnavailableError
      @model_unavailable = true
      nil
    rescue RubyLLM::Error
      nil
    end

    def prompt_for(description)
      examples = description.examples.map { |example| "- #{example.title}: #{example.snippet}" }.join("\n")
      <<~PROMPT
        These forum excerpts belong to one discussion theme:

        #{examples}

        Name the theme in 2 to 4 words, as plain text with no quotes, for example: Database migrations in production
      PROMPT
    end
  end
end
