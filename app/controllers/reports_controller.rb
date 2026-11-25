class ReportsController < ApplicationController
  rescue_from Date::Error, with: :invalid_week

  def create
    week = requested_week
    Report.request_comparison(week).each(&:generate_later)
    redirect_to compare_reports_path(week_of: week), status: :see_other
  end

  def compare
    @comparison = Reports::Comparison.for(requested_week)
  end

  private

  def requested_week
    Week.parse(params.require(:week_of))
  end

  def invalid_week
    render plain: "week_of must be a date like 2026-11-16", status: :bad_request
  end
end
