namespace :search do
  desc "Print the chunks most similar to a query, to sanity-check retrieval"
  task :similar, [ :query ] => :environment do |_task, args|
    abort 'Usage: bin/rails "search:similar[your query]"' if args[:query].blank?

    Search::SimilarChunks.new.call(args[:query]).each.with_index(1) { |match, rank| puts "#{rank}. #{match}" }
  rescue Embeddings::UnavailableError => error
    abort error.message
  end
end
