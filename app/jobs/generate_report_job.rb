class GenerateReportJob < ApplicationJob
  # Ollama shares one GPU between concurrent requests, so parallel reports all slow down and can time out.
  # One report generates at a time; the others wait in the queue. The lock outlasts a slow generation.
  limits_concurrency key: "ollama", to: 1, duration: 15.minutes

  queue_as :default

  def perform(report_id)
    report = Report.find(report_id)
    Reports::Generator.for(report).generate(report)
  end
end
