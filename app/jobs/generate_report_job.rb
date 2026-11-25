class GenerateReportJob < ApplicationJob
  queue_as :default

  def perform(report_id)
    report = Report.find(report_id)
    Reports::Generator.for(report).generate(report)
  end
end
