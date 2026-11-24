namespace :chunks do
  desc "Split every post into title-prefixed chunks, keeping unchanged chunks and their embeddings"
  task sync: :environment do
    puts Chunking::ChunkSyncer.new.sync_all
  end
end
