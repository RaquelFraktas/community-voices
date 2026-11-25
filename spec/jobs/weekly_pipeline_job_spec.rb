require "rails_helper"

RSpec.describe WeeklyPipelineJob do
  include ActiveJob::TestHelper

  around { |example| travel_to(Time.zone.parse("2026-11-30T06:00:00Z")) { example.run } }

  let(:calls) { [] }
  let(:week) { Week.new(Date.new(2026, 11, 23)) }

  def fake_step(name, summary: "done", error: nil)
    step = Object.new
    log = calls
    step.define_singleton_method(:name) { name }
    step.define_singleton_method(:call) do |for_week, force:|
      log << [ name, for_week, force ]
      raise error if error

      summary
    end
    step
  end

  let(:steps) { %w[ingest chunk\ sync embed themes reports].map { |name| fake_step(name, summary: "#{name} ok") } }

  before { allow(WeeklyPipeline).to receive(:steps).and_return(steps) }

  it "runs every step in order for the last complete week" do
    described_class.perform_now

    expect(calls.map(&:first)).to eq([ "ingest", "chunk sync", "embed", "themes", "reports" ])
    expect(calls.map(&:second)).to all(eq(week))
  end

  it "returns and logs a one-line summary per step" do
    allow(Rails.logger).to receive(:info)

    summaries = described_class.perform_now

    expect(summaries).to eq([ "ingest: ingest ok", "chunk sync: chunk sync ok", "embed: embed ok", "themes: themes ok",
                              "reports: reports ok" ])
    summaries.each { |summary| expect(Rails.logger).to have_received(:info).with("[WeeklyPipeline] #{summary}") }
  end

  it "passes force on to every step" do
    described_class.perform_now(force: true)

    expect(calls.map(&:third)).to all(be(true))
  end

  it "does not force by default" do
    described_class.perform_now

    expect(calls.map(&:third)).to all(be(false))
  end

  it "can run for a given week" do
    described_class.perform_now(week_of: "2026-11-18")

    expect(calls.map(&:second)).to all(eq(Week.new(Date.new(2026, 11, 16))))
  end

  context "when a step fails" do
    let(:steps) do
      [ fake_step("ingest"), fake_step("chunk sync"), fake_step("embed", error: Embeddings::UnavailableError.new("Start it with: ollama serve")),
        fake_step("themes"), fake_step("reports") ]
    end

    it "stops at that step with a message naming it" do
      expect { described_class.perform_now }
        .to raise_error(described_class::StepFailed, "Weekly pipeline stopped at embed: Start it with: ollama serve")

      expect(calls.map(&:first)).to eq([ "ingest", "chunk sync", "embed" ])
    end

    it "logs the failure" do
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.to raise_error(described_class::StepFailed)
      expect(Rails.logger).to have_received(:error).with("[WeeklyPipeline] Weekly pipeline stopped at embed: Start it with: ollama serve")
    end
  end

  it "is scheduled for Monday mornings in development and production" do
    %w[development production].each do |environment|
      schedule = WeeklyPipeline::Schedule.new(environment: environment)

      expect(schedule.description).to eq("every monday at 6am")
      expect(schedule.next_run_at(Time.zone.parse("2026-11-25T10:00:00Z"))).to eq(Time.zone.parse("2026-11-30T06:00:00Z"))
    end
  end

  it "is not scheduled in the test environment" do
    expect(WeeklyPipeline::Schedule.new.next_run_at).to be_nil
  end
end
