module Search
  class SimilarChunks
    DEFAULT_LIMIT = 5
    SNIPPET_LENGTH = 100
    # Without this, HNSW finds its nearest candidates first and filters them afterwards, so a time-filtered
    # search can return fewer matches than asked for. relaxed_order keeps scanning until the limit is met.
    ITERATIVE_SCAN = "SET LOCAL hnsw.iterative_scan = relaxed_order".freeze

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

    def call(query, limit: DEFAULT_LIMIT, since: nil, before: nil)
      query_vector = @client.embed_query(query)
      chunks = nearest_chunks(query_vector, since, before).limit(limit)
      chunks = since || before ? with_iterative_scan { chunks.to_a } : chunks.to_a

      chunks.map { |chunk| Match.new(chunk: chunk, distance: chunk.neighbor_distance) }.sort_by(&:distance)
    end

    private

    def nearest_chunks(query_vector, since, before)
      candidates(since, before).nearest_neighbors(:embedding, query_vector, distance: "cosine")
    end

    def candidates(since, before)
      chunks = Chunk.includes(:post)
      return chunks unless since || before

      chunks.joins(:post).merge(Post.posted_between(since, before))
    end

    def with_iterative_scan
      Chunk.transaction do
        Chunk.connection.execute(ITERATIVE_SCAN)
        yield
      end
    end
  end
end
