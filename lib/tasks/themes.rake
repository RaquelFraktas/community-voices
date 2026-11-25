namespace :themes do
  desc "Cluster, label and project the chunks of the 6 weeks ending with a week (default: the most recent complete week)"
  task :build, [ :week_of ] => :environment do |_task, args|
    week = args[:week_of] ? Week.parse(args[:week_of]) : Week.most_recent_complete
    abort 'No posts yet. Run bin/rails "pipeline:refresh[42]" first.' unless week

    puts "Building themes for #{week.label}...", ""
    puts Themes::TrendTable.new(Themes::Builder.new.build(week))
    puts "", "See them on a map: bin/dev, then open /embeddings?week_of=#{week.to_param}"
  rescue ArgumentError => error
    abort error.message
  end
end
