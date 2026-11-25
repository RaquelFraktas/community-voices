namespace :reports do
  desc "Generate the RAG and baseline reports for a week (default: the most recent complete week) and print the metrics"
  task :generate, [ :week_of ] => :environment do |_task, args|
    week = args[:week_of] ? Week.parse(args[:week_of]) : Week.most_recent_complete
    abort 'No posts yet. Run bin/rails "pipeline:refresh[7]" first.' unless week

    puts "Generating reports for #{week.label} (#{week.posts.count} posts)..."
    reports = Report.request_comparison(week).map { |report| Reports::Generator.for(report).generate(report) }
    reports.each { |report| puts "#{report.variant}: #{report.status}#{" – #{report.error_message}" if report.failed?}" }
    abort "Reports failed; see the errors above." if reports.any?(&:failed?)

    puts "", Reports::MetricsTable.new(Reports::Comparison.for(week).metrics)
    puts "", "View them side by side: bin/dev, then open /reports/compare?week_of=#{week.to_param}"
  end
end
