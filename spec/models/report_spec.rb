require "rails_helper"

RSpec.describe Report do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  it "starts out pending" do
    expect(described_class.create!(week_of: week.starts_on, variant: :rag)).to be_pending
  end

  it "rejects unknown variants and statuses" do
    expect(described_class.new(week_of: week.starts_on, variant: "other")).not_to be_valid
    expect(described_class.new(week_of: week.starts_on, variant: :rag, status: "lost")).not_to be_valid
  end

  describe ".request_comparison" do
    it "creates a pending RAG report and a pending baseline report for the week" do
      reports = described_class.request_comparison(week)

      expect(reports.map(&:variant)).to contain_exactly("rag", "baseline")
      expect(reports).to all(be_pending)
      expect(reports.map(&:week_of)).to all(eq(week.starts_on))
    end
  end

  describe ".latest" do
    it "returns the newest report of a variant for the week" do
      described_class.create!(week_of: week.starts_on, variant: :rag, created_at: 1.hour.ago)
      newest = described_class.create!(week_of: week.starts_on, variant: :rag)
      described_class.create!(week_of: week.starts_on, variant: :baseline)

      expect(described_class.latest(week, :rag)).to eq(newest)
    end

    it "returns nil when the week has no report of that variant" do
      expect(described_class.latest(week, :baseline)).to be_nil
    end
  end

  describe "timing out" do
    include ActiveJob::TestHelper

    def report_last_touched(minutes_ago, status:)
      described_class.create!(week_of: week.starts_on, variant: :rag, status: status,
                              updated_at: minutes_ago.minutes.ago)
    end

    %w[pending generating].each do |status|
      it "treats a report #{status} for longer than the timeout as failed" do
        report = report_last_touched(11, status: status)

        expect(report).to be_timed_out
        expect(report).not_to be_in_progress
        expect(report).to be_retryable
        expect(report.displayed_status).to eq("failed")
        expect(report.failure_message).to include("Timed out", "still #{status}", "10 minutes", "worker stopped")
      end

      it "keeps a report #{status} within the timeout in progress" do
        report = report_last_touched(9, status: status)

        expect(report).not_to be_timed_out
        expect(report).to be_in_progress
        expect(report.displayed_status).to eq(status)
      end
    end

    context "with a custom timeout" do
      around do |example|
        ENV["REPORT_GENERATION_TIMEOUT_MINUTES"] = "3"
        example.run
      ensure
        ENV.delete("REPORT_GENERATION_TIMEOUT_MINUTES")
      end

      it "reads the timeout in minutes from REPORT_GENERATION_TIMEOUT_MINUTES" do
        expect(described_class.generation_timeout).to eq(3.minutes)
        expect(report_last_touched(4, status: :generating)).to be_timed_out
        expect(report_last_touched(2, status: :generating)).not_to be_timed_out
      end
    end

    it "defaults to a 10 minute timeout" do
      expect(described_class.generation_timeout).to eq(10.minutes)
    end

    it "never times out a finished report" do
      expect(report_last_touched(60, status: :complete)).not_to be_timed_out
      expect(report_last_touched(60, status: :failed)).not_to be_timed_out
    end

    it "shows a real failure's own error message" do
      report = described_class.create!(week_of: week.starts_on, variant: :rag, status: :failed, error_message: "boom")

      expect(report.failure_message).to eq("boom")
    end

    it "can be retried, which resets it to pending and enqueues the job again" do
      report = report_last_touched(11, status: :generating)

      expect { report.retry_later }.to have_enqueued_job(GenerateReportJob).with(report.id)
      expect(report.reload).to have_attributes(status: "pending", error_message: nil)
      expect(report).to be_in_progress
    end

    it "is not retryable once complete" do
      expect(report_last_touched(60, status: :complete)).not_to be_retryable
    end
  end

  it "is in progress while pending or generating" do
    report = described_class.new(week_of: week.starts_on, variant: :rag)

    expect(%w[pending generating complete failed].index_with { |status| report.tap { report.status = status }.in_progress? })
      .to eq("pending" => true, "generating" => true, "complete" => false, "failed" => false)
  end
end
