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

    def build(week:, entries:, trends: [])
      user = template.result_with_hash(week: week, entries: entries, trends: trends, trend_weeks: trend_weeks(trends),
                                       max_citations: ComparisonMetrics::MAX_CITATIONS_PER_GROUP)
      Prompt.new(system: SYSTEM_PROMPT, user: user)
    end

    private

    def trend_weeks(trends)
      trends.first&.weekly_counts&.keys.to_a.map { |starts_on| starts_on.strftime("%b %-d") }
    end

    def template
      @template ||= ERB.new(TEMPLATE_PATH.read, trim_mode: "-")
    end
  end
end
