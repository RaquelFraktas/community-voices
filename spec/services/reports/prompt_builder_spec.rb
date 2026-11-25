require "rails_helper"

RSpec.describe Reports::PromptBuilder do
  subject(:builder) { described_class.new }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:entries) do
    [
      Reports::ContextEntry.new(number: 1, post_title: "Rails 8.1.2 released", url: "https://example.com/1",
                                posted_at: Time.zone.parse("2026-11-17 09:00"), content: "Rails 8.1.2 is out."),
      Reports::ContextEntry.new(number: 2, post_title: "Kamal deploy hangs", url: "https://example.com/2",
                                posted_at: Time.zone.parse("2026-11-18 09:00"), content: "My deploy hangs.")
    ]
  end

  let(:weeks) { Array.new(3) { |i| week.starts_on - (2 - i).weeks } }
  let(:trends) do
    [
      Themes::TrendAnalyzer::Trend.new(cluster_id: 1, label: "kamal · deploy · hangs", momentum: 2.4,
                                       weekly_counts: weeks.zip([ 1, 1, 4 ]).to_h, classification: "rising"),
      Themes::TrendAnalyzer::Trend.new(cluster_id: 2, label: "activestorage · cdn", momentum: nil,
                                       weekly_counts: weeks.zip([ 0, 0, 2 ]).to_h, classification: "new")
    ]
  end
  let(:rag_prompt) { builder.build(week: week, entries: entries, trends: trends) }
  let(:baseline_prompt) { builder.build(week: week, entries: []) }

  it "asks for the four sections, with reasoning for each prediction" do
    expect(rag_prompt.user).to include(
      "## Summary", "## Top discussions this past week", "## Recurring themes", "## Predictions for next week",
      "reasoning"
    )
  end

  it "tells both variants to start with the Summary instead of repeating the title" do
    [ rag_prompt, baseline_prompt ].each do |prompt|
      expect(prompt.user).to include("Start your answer directly with \"## Summary\". Do not repeat the title or the week.")
    end
  end

  it "includes the week's dates" do
    expect(rag_prompt.user).to include("Nov 16 – Nov 22, 2026", "2026-11-16 to 2026-11-22")
  end

  it "numbers each context entry with its title, date, url and content" do
    expect(rag_prompt.user).to include(
      "[1] \"Rails 8.1.2 released\" (posted 2026-11-17, https://example.com/1)\nRails 8.1.2 is out.",
      "[2] \"Kamal deploy hangs\" (posted 2026-11-18, https://example.com/2)\nMy deploy hangs."
    )
  end

  it "asks the RAG variant to cite its sources as [n], last, so the rule is fresh when the model starts writing" do
    expect(rag_prompt.user.strip).to end_with("Only use numbers from 1 to 2.")
    expect(rag_prompt.user).to include("Citation rule", "[1][4]", "Each prediction must cite the excerpts")
  end

  it "limits the RAG variant to three directly supporting citations per sentence, matching the metrics" do
    expect(Reports::ComparisonMetrics::MAX_CITATIONS_PER_GROUP).to eq(3)
    expect(rag_prompt.user).to include("Cite at most 3 excerpts per sentence, and only ones that\ndirectly support it.")
    expect(baseline_prompt.user).not_to include("Cite at most")
  end

  it "lists each theme's weekly counts and trend for the RAG variant, after the sources and before the citation rule" do
    user = rag_prompt.user

    expect(user).to include(
      "## Theme trends", "from Nov 2 to Nov 16 (this week last)",
      "- kamal · deploy · hangs: 1, 1, 4 (rising)", "- activestorage · cdn: 0, 0, 2 (new)"
    )
    expect(user.index("## Sources")).to be < user.index("## Theme trends")
    expect(user.index("## Theme trends")).to be < user.index("Citation rule")
  end

  it "leaves the trends section out when the retriever returned no trends" do
    expect(builder.build(week: week, entries: entries).user).not_to include("## Theme trends")
  end

  it "gives the baseline no context, no trends and no citation instructions" do
    expect(baseline_prompt.user).to include("No forum excerpts or theme trends are provided")
    expect(baseline_prompt.user).not_to include("Rails 8.1.2 is out", "[1]", "Citation", "## Theme trends", "kamal")
  end

  it "asks both variants to base predictions on rising and new themes" do
    [ rag_prompt, baseline_prompt ].each do |prompt|
      expect(prompt.user).to include("Base each prediction\non themes that are rising or new this week")
    end
  end

  it "shares every instruction word for word, differing only in the sources and trends at the end" do
    before_sources = ->(prompt) { prompt.user.split("## Sources").first }

    expect(before_sources.call(rag_prompt)).to eq(before_sources.call(baseline_prompt))
    expect(before_sources.call(rag_prompt)).to include("## Instructions", "## Predictions for next week")
    expect(before_sources.call(rag_prompt)).not_to include("## Theme trends")
    expect(rag_prompt.system).to eq(baseline_prompt.system)
  end

  it "renders the full prompt with both messages" do
    expect(rag_prompt.to_s).to start_with("SYSTEM:\n#{described_class::SYSTEM_PROMPT}\n\nUSER:\nWrite this week's")
  end
end
