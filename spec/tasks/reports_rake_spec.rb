require "rails_helper"
require "rake"

RSpec.describe "rake reports:generate" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  before { Rake::Task["reports:generate"].reenable }

  around { |example| travel_to(Time.zone.parse("2026-11-24T12:00:00Z")) { example.run } }

  def run_task(*args)
    expect { Rake::Task["reports:generate"].invoke(*args) }.to output.to_stdout
  end

  let!(:last_week_chunk) do
    create_chunk(post: create_post(title: "Rails 8.1.2 released", posted_at: Time.zone.parse("2026-11-18 10:00")))
  end

  it "generates both reports synchronously and prints the metrics" do
    expect { Rake::Task["reports:generate"].invoke("2026-11-16") }.to output(
      a_string_including(
        "Generating reports for Nov 16 – Nov 22, 2026 (1 posts)...", "rag: complete", "baseline: complete",
        "Metric", "Valid citations", "Invalid citations", "/reports/compare?week_of=2026-11-16"
      )
    ).to_stdout

    expect(Report.where(week_of: Date.new(2026, 11, 16)).map(&:status)).to all(eq("complete"))
    expect(Report.find_by!(variant: :rag).retrievals.map(&:chunk)).to eq([ last_week_chunk ])
  end

  it "defaults to the most recent complete week" do
    create_post(posted_at: Time.zone.parse("2026-11-24 09:00"))

    run_task

    expect(Report.distinct.pluck(:week_of)).to eq([ Date.new(2026, 11, 16) ])
  end

  it "stops with the error when a report fails" do
    allow_any_instance_of(Llm::FakeChatClient).to receive(:complete)
      .and_raise(Llm::UnavailableError, "Ollama has no model named llama3.2. Download it with: ollama pull llama3.2")

    expect { Rake::Task["reports:generate"].invoke("2026-11-16") }
      .to raise_error(SystemExit)
      .and output(/rag: failed – Llm::UnavailableError: .*ollama pull llama3\.2/).to_stdout
      .and output(/Reports failed/).to_stderr
  end
end

RSpec.describe Reports::MetricsTable do
  it "aligns labels left and numbers right" do
    rows = [ Reports::ComparisonMetrics::Row.new("Words", 120, 95), Reports::ComparisonMetrics::Row.new("Valid citations", 7, 0) ]
    metrics = instance_double(Reports::ComparisonMetrics, rows: rows)

    expect(described_class.new(metrics).to_s).to eq(<<~TABLE.chomp)
      Metric           RAG  Baseline
      ---------------  ---  --------
      Words            120        95
      Valid citations    7         0
    TABLE
  end
end
