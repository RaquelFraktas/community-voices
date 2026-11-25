namespace :seeds do
  desc "Export the last 6 weeks of posts, embeddings, themes and reports to db/seeds/ for bin/rails db:seed"
  task export: :environment do
    week = Week.most_recent_complete
    abort 'No posts yet. Run bin/rails "pipeline:weekly" first.' unless week

    path = Seeds::Exporter.new(last_week: week).export
    snapshot = JSON.parse(Zlib::GzipReader.open(path, &:read))
    counts = %w[posts chunks clusterings reports].map { |key| "#{snapshot[key].size} #{key}" }.join(", ")
    puts "Exported #{counts} up to #{week.label}"
    puts "to #{path.relative_path_from(Rails.root)} (#{ActiveSupport::NumberHelper.number_to_human_size(File.size(path))})"
  end
end
