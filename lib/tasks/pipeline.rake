namespace :pipeline do
  desc "Ingest posts from the last N days (default 7), then sync chunks and embed the pending ones"
  task :refresh, [ :days ] => :environment do |_task, args|
    Rake::Task["ingest:discourse"].invoke(*args[:days])
    Rake::Task["chunks:sync"].invoke
    Rake::Task["embed:pending"].invoke
  end

  desc "Run the weekly pipeline now for the last complete week; pass force to rebuild themes and regenerate reports"
  task :weekly, [ :force ] => :environment do |_task, args|
    force = args[:force].to_s == "force"
    puts WeeklyPipelineJob.perform_now(force: force)
  rescue WeeklyPipelineJob::StepFailed => error
    abort error.message
  end
end
