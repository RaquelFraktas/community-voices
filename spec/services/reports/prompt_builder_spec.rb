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

  let(:rag_prompt) { builder.build(week: week, entries: entries) }
  let(:baseline_prompt) { builder.build(week: week, entries: []) }

  it "asks for the four sections, with reasoning for each prediction" do
    expect(rag_prompt.user).to include(
      "## Summary", "## Top discussions this past week", "## Recurring themes", "## Predictions for next week",
      "reasoning"
    )
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
    expect(rag_prompt.user).to include("Citation rule", "[1][4]")
  end

  it "gives the baseline no context and no citation instructions" do
    expect(baseline_prompt.user).to include("No forum excerpts are provided")
    expect(baseline_prompt.user).not_to include("Rails 8.1.2 is out", "[1]", "Citation")
  end

  it "differs between the variants only in the sources section at the end" do
    before_sources = ->(prompt) { prompt.user.split("## Sources").first }

    expect(before_sources.call(rag_prompt)).to eq(before_sources.call(baseline_prompt))
    expect(before_sources.call(rag_prompt)).to include("## Instructions", "## Predictions for next week")
    expect(rag_prompt.system).to eq(baseline_prompt.system)
  end

  it "renders the full prompt with both messages" do
    expect(rag_prompt.to_s).to start_with("SYSTEM:\n#{described_class::SYSTEM_PROMPT}\n\nUSER:\nWrite this week's")
  end
end
