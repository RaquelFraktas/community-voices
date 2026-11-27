require "rails_helper"

RSpec.describe GenerateReportJob do
  include ActiveJob::TestHelper

  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  it "generates the report with the generator for its variant" do
    report = Report.create!(week_of: week.starts_on, variant: :baseline)

    described_class.perform_now(report.id)

    expect(report.reload).to have_attributes(status: "complete", body: Llm::FakeChatClient::CANNED_RESPONSE)
  end

  it "generates one report at a time, so parallel requests do not slow Ollama down" do
    job = described_class.new(Report.create!(week_of: week.starts_on, variant: :rag).id)
    other_job = described_class.new(Report.create!(week_of: week.starts_on, variant: :baseline).id)

    expect(described_class.concurrency_limit).to eq(1)
    expect(job.concurrency_key).to eq(other_job.concurrency_key)
    expect(described_class.concurrency_duration).to be > Report.generation_timeout
  end

  it "is enqueued by Report#generate_later" do
    report = Report.create!(week_of: week.starts_on, variant: :rag)

    expect { report.generate_later }.to have_enqueued_job(described_class).with(report.id)
  end
end
