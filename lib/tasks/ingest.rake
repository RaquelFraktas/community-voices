namespace :ingest do
  desc "Ingest posts from discuss.rubyonrails.org published in the last N days (default 7)"
  task :discourse, [ :days ] => :environment do |_task, args|
    args.with_defaults(days: Ingest::DiscourseFetcher::DEFAULT_WINDOW.in_days.to_i)
    fetcher = Ingest::DiscourseFetcher.new(window: Integer(args[:days]).days)

    puts Ingest::Pipeline.new(fetcher: fetcher).run
  end
end
