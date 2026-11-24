namespace :pipeline do
  desc "Ingest posts from the last N days (default 7), then sync chunks and embed the pending ones"
  task :refresh, [ :days ] => :environment do |_task, args|
    Rake::Task["ingest:discourse"].invoke(*args[:days])
    Rake::Task["chunks:sync"].invoke
    Rake::Task["embed:pending"].invoke
  end
end
