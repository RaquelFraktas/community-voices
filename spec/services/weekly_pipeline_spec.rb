require "rails_helper"

RSpec.describe WeeklyPipeline do
  around { |example| travel_to(Time.zone.parse("2026-11-24T12:00:00Z")) { example.run } }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  it "lists the steps in pipeline order" do
    expect(described_class.steps.map(&:name)).to eq([ "ingest", "chunk sync", "embed", "themes", "reports" ])
  end

  describe WeeklyPipeline::IngestStep do
    it "fetches far enough back to cover the whole week" do
      requested = nil
      fetcher = instance_double(Ingest::DiscourseFetcher, fetch: [])
      step = described_class.new(fetcher_for: ->(window) { requested = window } >> ->(_) { fetcher })

      expect(step.call(week)).to eq("Fetched 0 posts (0 new). 0 posts stored in total.")
      expect(Time.current - requested).to be <= week.starts_at
    end
  end

  describe WeeklyPipeline::ThemesStep do
    before { create_themed_chunks(week: week, titles_by_group: [ "Migrations", "ActiveStorage CDN", "Kamal deploys" ]) }

    it "builds the week's themes" do
      expect(described_class.new.call(week)).to eq("Built 3 themes from 12 chunks.")
    end

    it "skips a week that already has themes" do
      described_class.new.call(week)

      expect { expect(described_class.new.call(week)).to start_with("Skipped") }.not_to change(Clustering, :count)
    end

    it "rebuilds when forced" do
      described_class.new.call(week)

      expect { described_class.new.call(week, force: true) }.to change(Clustering, :count).by(1)
    end
  end

  describe WeeklyPipeline::ReportsStep do
    before { create_themed_chunks(week: week, titles_by_group: [ "Migrations", "ActiveStorage CDN", "Kamal deploys" ]) }

    it "generates both reports" do
      expect(described_class.new.call(week)).to eq("Generated both reports for #{week.label}.")
      expect(Report.where(week_of: week.starts_on).map(&:status)).to contain_exactly("complete", "complete")
    end

    it "skips a week that already has a complete pair" do
      described_class.new.call(week)

      expect { expect(described_class.new.call(week)).to start_with("Skipped") }.not_to change(Report, :count)
    end

    it "regenerates when forced" do
      described_class.new.call(week)

      expect { described_class.new.call(week, force: true) }.to change(Report, :count).by(2)
    end

    it "generates again when the existing pair is not complete" do
      Report.create!(week_of: week.starts_on, variant: :rag, status: :failed)
      Report.create!(week_of: week.starts_on, variant: :baseline, status: :complete)

      expect { described_class.new.call(week) }.to change(Report, :count).by(2)
    end

    it "fails with the reports' errors when generation fails" do
      allow_any_instance_of(Llm::FakeChatClient).to receive(:complete).and_raise(Llm::UnavailableError, "Start it with: ollama serve")

      expect { described_class.new.call(week) }.to raise_error(/rag: Llm::UnavailableError: Start it with: ollama serve/)
    end
  end
end

RSpec.describe "WeeklyPipelineJob run twice with real steps" do
  around { |example| travel_to(Time.zone.parse("2026-11-24T12:00:00Z")) { example.run } }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:fetched_posts) do
    Array.new(12) do |i|
      group = %w[Migrations ActiveStorage Kamal][i % 3]
      Ingest::FetchedPost.new(source: "discourse", source_id: i.to_s, title: "#{group} thread #{i % 3}",
                              body: "#{group} discussion number #{i}, with enough text to chunk.", author: "dhh",
                              url: "https://forum.test/#{i}", posted_at: week.starts_at + (i % 7).days, reply_count: 0)
    end
  end

  before do
    fetcher = instance_double(Ingest::DiscourseFetcher, fetch: fetched_posts)
    ingest = WeeklyPipeline::IngestStep.new(fetcher_for: ->(_window) { fetcher })
    allow(WeeklyPipeline).to receive(:steps).and_return(
      [ ingest, WeeklyPipeline::ChunkStep.new, WeeklyPipeline::EmbedStep.new, WeeklyPipeline::ThemesStep.new,
        WeeklyPipeline::ReportsStep.new ]
    )
  end

  def record_counts
    [ Post, Chunk, Clustering, Report, Retrieval ].to_h { |model| [ model.name, model.count ] }
  end

  it "creates no duplicates on the second run, and skips the themes and reports it already has" do
    WeeklyPipelineJob.perform_now(week_of: week.to_param)
    after_first_run = record_counts

    summaries = WeeklyPipelineJob.perform_now(week_of: week.to_param)

    expect(record_counts).to eq(after_first_run)
    expect(after_first_run).to include("Post" => 12, "Chunk" => 12, "Clustering" => 1, "Report" => 2)
    expect(summaries).to include("embed: Embedded 0 chunks.", a_string_starting_with("themes: Skipped"),
                                 a_string_starting_with("reports: Skipped"))
  end
end
