require "rails_helper"

RSpec.describe "Reports", type: :request do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:post_in_week) do
    create_post(title: "Upgrading to Rails 8.1", posted_at: Time.zone.parse("2026-11-18 10:00"),
                source_id: "upgrade-1")
  end

  def complete_report(variant, body:, seconds: 3.2)
    Report.create!(week_of: week.starts_on, variant: variant, status: :complete, body: body,
                   llm_model: "llama3.2", generation_seconds: seconds)
  end

  describe "GET /" do
    it "lists the weeks that have posts with a button to generate reports" do
      post_in_week

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nov 16 – Nov 22, 2026", "Generate reports")
    end
  end

  describe "POST /reports" do
    include ActiveJob::TestHelper

    it "creates pending RAG and baseline reports, enqueues their jobs and shows the comparison" do
      expect { post reports_path, params: { week_of: "2026-11-18" } }
        .to change(Report, :count).by(2).and have_enqueued_job(GenerateReportJob).twice

      expect(Report.all).to all(be_pending)
      expect(Report.pluck(:week_of).uniq).to eq([ week.starts_on ])
      expect(response).to redirect_to(compare_reports_path(week_of: "2026-11-16"))
    end

    it "rejects a malformed week" do
      post reports_path, params: { week_of: "next tuesday" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /reports/compare" do
    context "when both reports are complete" do
      let!(:rag) { complete_report(:rag, body: "## Summary\nUpgrading to Rails 8.1 dominated [1]. Also [9].") }

      before do
        complete_report(:baseline, body: "## Summary\nPeople discussed Hotwire [1].", seconds: 1.5)
        chunk = create_chunk(post: post_in_week)
        rag.retrievals.create!(retrieval_attributes_for(chunk, rank: 1, query_label: "new releases and upgrades",
                                                               distance: 0.234))
      end

      it "shows the metrics table above both rendered reports" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response).to have_http_status(:ok)
        body = response.body
        expect(body).to include("Valid citations", "Invalid citations", "Post titles mentioned (of 1)")
        expect(body.index("Valid citations")).to be < body.index("<h2>Summary</h2>")
        expect(body.scan("<h2>Summary</h2>").size).to eq(2)
      end

      it "links the RAG report's citations to their source posts and flags the rest" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response.body).to include(%(<a href="#{post_in_week.url}" class="citation"))
        expect(response.body.scan("citation--invalid").size).to eq(2)
      end

      it "lists the retrieved context in a collapsible panel" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response.body).to include("<details", "Retrieved context (1 chunks)", "Upgrading to Rails 8.1",
                                         "new releases and upgrades", "distance 0.234", "Some content")
      end

      it "does not refresh the page" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response.body).not_to include('http-equiv="refresh"')
      end
    end

    context "while reports are being generated" do
      before do
        Report.create!(week_of: week.starts_on, variant: :rag, status: :generating)
        Report.create!(week_of: week.starts_on, variant: :baseline, status: :pending)
      end

      it "shows their status and refreshes automatically" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response.body).to include("generating", "pending", 'http-equiv="refresh"')
        expect(response.body).not_to include("Valid citations")
      end
    end

    it "shows why a report failed, with a retry button" do
      report = Report.create!(week_of: week.starts_on, variant: :rag, status: :failed,
                              error_message: "Llm::UnavailableError: Start it with: ollama serve")

      get compare_reports_path(week_of: "2026-11-16")

      expect(response.body).to include("failed", "Start it with: ollama serve", report_retry_path(report), "Retry")
    end

    context "when generation was abandoned, e.g. by a server restart" do
      let!(:stuck) do
        Report.create!(week_of: week.starts_on, variant: :rag, status: :generating, updated_at: 11.minutes.ago)
      end

      before { complete_report(:baseline, body: "## Summary\nDone.") }

      it "shows the stuck report as failed with a retry button, and stops refreshing" do
        get compare_reports_path(week_of: "2026-11-16")

        expect(response.body).to include("badge--failed", "Timed out", report_retry_path(stuck))
        expect(response.body).not_to include('http-equiv="refresh"', "badge--generating")
      end

      it "lets the week be generated again from the home page" do
        post_in_week

        get root_path

        expect(response.body).to include("badge--failed")
        expect(response.body).not_to match(/<button[^>]*disabled[^>]*>Generate reports/)
      end
    end
  end

  describe "POST /reports/:id/retry" do
    include ActiveJob::TestHelper

    it "requeues a timed-out report and returns to the comparison, which refreshes again" do
      stuck = Report.create!(week_of: week.starts_on, variant: :rag, status: :generating, updated_at: 11.minutes.ago)

      expect { post report_retry_path(stuck) }.to have_enqueued_job(GenerateReportJob).with(stuck.id)

      expect(stuck.reload).to be_pending
      expect(response).to redirect_to(compare_reports_path(week_of: "2026-11-16"))
      follow_redirect!
      expect(response.body).to include('http-equiv="refresh"')
    end

    it "requeues a failed report" do
      failed = Report.create!(week_of: week.starts_on, variant: :baseline, status: :failed, error_message: "boom")

      expect { post report_retry_path(failed) }.to have_enqueued_job(GenerateReportJob).with(failed.id)
      expect(failed.reload).to have_attributes(status: "pending", error_message: nil)
    end

    it "leaves a report that is still running alone" do
      running = Report.create!(week_of: week.starts_on, variant: :rag, status: :generating)

      expect { post report_retry_path(running) }.not_to have_enqueued_job(GenerateReportJob)
      expect(running.reload).to be_generating
    end

    it "offers to generate reports for a week without any" do
      get compare_reports_path(week_of: "2026-11-16")

      expect(response.body).to include("No reports for this week yet", "Generate reports")
    end
  end
end
