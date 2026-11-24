namespace :embed do
  desc "Embed every chunk that has no embedding yet"
  task pending: :environment do
    puts "Embedded #{Embeddings::PendingEmbedder.new.embed_pending} chunks."
  rescue Embeddings::UnavailableError => error
    abort error.message
  end
end
