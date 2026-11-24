module Embeddings
  class PendingEmbedder
    BATCH_SIZE = 32

    def initialize(client: Embeddings.client, batch_size: BATCH_SIZE)
      @client = client
      @batch_size = batch_size
    end

    def embed_pending
      Chunk.pending_embedding.select(:id, :content).find_in_batches(batch_size: @batch_size).sum do |chunks|
        embed_batch(chunks)
      end
    end

    private

    def embed_batch(chunks)
      vectors = @client.embed_documents(chunks.map(&:content))
      Chunk.transaction do
        chunks.zip(vectors).each { |chunk, vector| chunk.update_columns(embedding: vector) }
      end
      chunks.size
    end
  end
end
