module Search
  class SimilarChunks
    DEFAULT_LIMIT = 5
    SNIPPET_LENGTH = 100

    Match = Data.define(:chunk, :distance) do
      delegate :post, :content, to: :chunk

      def snippet
        content.delete_prefix(post.title).squish.first(SNIPPET_LENGTH)
      end

      def to_s
        format("%.3f  %s\n       %s", distance, post.title, snippet)
      end
    end

    def initialize(client: Embeddings.client)
      @client = client
    end

    def call(query, limit: DEFAULT_LIMIT, since: nil)
      nearest_chunks(@client.embed_query(query), since)
        .limit(limit)
        .map { |chunk| Match.new(chunk: chunk, distance: chunk.neighbor_distance) }
    end

    private

    def nearest_chunks(query_vector, since)
      candidates(since).nearest_neighbors(:embedding, query_vector, distance: "cosine")
    end

    def candidates(since)
      chunks = Chunk.includes(:post)
      since ? chunks.joins(:post).merge(Post.posted_since(since)) : chunks
    end
  end
end
