require "rails_helper"
require "rake"

RSpec.describe "rake reports:generate" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  before { Rake::Task["reports:generate"].reenable }

  around { |example| travel_to(Time.zone.parse("2026-11-24T12:00:00Z")) { example.run } }

  # An abort inside the task raises SystemExit, which would end the whole RSpec run instead of failing.
  def run_task(*args, printing: anything)
    expect { expect { Rake::Task["reports:generate"].invoke(*args) }.to output(printing).to_stdout }
      .not_to raise_error
  end

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let!(:week_chunks) do
    create_themed_chunks(week: week, titles_by_group: [ "Zero-downtime migrations", "ActiveStorage CDN", "Kamal deploys" ])
  end

  it "generates both reports synchronously and prints the metrics" do
    run_task("2026-11-16", printing: a_string_including(
      "Generating reports for Nov 16 – Nov 22, 2026 (12 posts, RAG context from themes)...",
      "rag: complete", "baseline: complete", "Themes: 3 clusters from 12 chunks",
      "Metric", "Valid citations", "Invalid citations", "/reports/compare?week_of=2026-11-16"
    ))

    expect(Report.where(week_of: week.starts_on).map(&:status)).to all(eq("complete"))
    expect(Report.find_by!(variant: :rag).retrievals.map(&:chunk)).to all(be_in(week_chunks))
  end

  it "builds the week's themes for the RAG report when there are none yet" do
    expect { run_task("2026-11-16") }.to change(Clustering, :count).by(1)

    rag = Report.find_by!(variant: :rag)
    expect(rag.clustering).to eq(Clustering.latest_for(week))
    expect(rag.retrievals.map(&:query_label)).to all(be_in(rag.clustering.clusters.map(&:label)))
    expect(Report.find_by!(variant: :baseline).clustering).to be_nil
  end

  it "reuses existing themes for the week" do
    Themes::Builder.new.build(week)

    expect { run_task("2026-11-16") }.not_to change(Clustering, :count)
  end

  it "defaults to the most recent complete week" do
    create_post(posted_at: Time.zone.parse("2026-11-24 09:00"))

    run_task

    expect(Report.distinct.pluck(:week_of)).to eq([ week.starts_on ])
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
