module WeeklyPipeline
  # Generates the week's RAG and baseline reports, unless a complete pair already exists.
  class ReportsStep
    def name = "reports"

    def call(week, force: false)
      return "Skipped: #{week.label} already has a complete pair of reports (pass force to regenerate)." if complete_pair?(week) && !force

      reports = Report.request_comparison(week).map { |report| Reports::Generator.for(report).generate(report) }
      failed = reports.select(&:failed?)
      raise failed.map { |report| "#{report.variant}: #{report.error_message}" }.join("; ") if failed.any?

      "Generated both reports for #{week.label}."
    end

    private

    def complete_pair?(week)
      Reports::Comparison.for(week).complete?
    end
  end
end
