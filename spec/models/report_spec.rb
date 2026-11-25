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

  it "is in progress while pending or generating" do
    report = described_class.new(week_of: week.starts_on, variant: :rag)

    expect(%w[pending generating complete failed].index_with { |status| report.tap { report.status = status }.in_progress? })
      .to eq("pending" => true, "generating" => true, "complete" => false, "failed" => false)
  end
end
