class ReportRetriesController < ApplicationController
  def create
    report = Report.find(params[:report_id])
    report.retry_later if report.retryable?
    redirect_to compare_reports_path(week_of: report.week), status: :see_other
  end
end
