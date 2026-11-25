module Reports
  class PromptBuilder
    TEMPLATE_PATH = Rails.root.join("app/prompts/community_voices.md.erb")
    SYSTEM_PROMPT = "You are the editor of the Community Voices Document, a weekly newsletter for the " \
                    "Ruby on Rails community. You write clear, accurate Markdown.".freeze

    Prompt = Data.define(:system, :user) do
      def to_s
        "SYSTEM:\n#{system}\n\nUSER:\n#{user}"
      end
    end

    def build(week:, entries:)
      Prompt.new(system: SYSTEM_PROMPT, user: template.result_with_hash(week: week, entries: entries))
    end

    private

    def template
      @template ||= ERB.new(TEMPLATE_PATH.read, trim_mode: "-")
    end
  end
end
