# Which chunks, posts and themes RAG reports retrieve most often.
class RetrievalStatsQuery
  DEFAULT_LIMIT = 20
  SNIPPET_LENGTH = 140

  ChunkRow = Data.define(:post_title, :post_url, :snippet, :retrievals_count, :last_retrieved_at)
  PostRow = Data.define(:title, :url, :retrievals_count)
  ThemeRow = Data.define(:label, :retrievals_count)

  def initialize(limit: DEFAULT_LIMIT)
    @limit = limit
  end

  def top_chunks
    Chunk.where(retrievals_count: 1..).joins(:post).left_joins(:retrievals).group("chunks.id", "posts.id")
         .select("chunks.*, posts.title AS post_title, posts.url AS post_url",
                 "MAX(retrievals.created_at) AS last_retrieved_at")
         .order(retrievals_count: :desc, last_retrieved_at: :desc, id: :asc).limit(@limit)
         .map { |chunk| chunk_row(chunk) }
  end

  def top_posts
    Post.joins(:chunks).where(chunks: { retrievals_count: 1.. }).group(:id)
        .select("posts.*, SUM(chunks.retrievals_count) AS total_retrievals")
        .order(total_retrievals: :desc, id: :asc).limit(@limit)
        .map { |post| PostRow.new(title: post.title, url: post.url, retrievals_count: post.total_retrievals) }
  end

  # Theme retrievals are labeled with their cluster; reports built from facet queries have no clustering.
  def top_themes
    Retrieval.joins(:report).where.not(reports: { clustering_id: nil }).group(:query_label)
             .order(count_all: :desc, query_label: :asc).limit(@limit).count
             .map { |label, count| ThemeRow.new(label: label, retrievals_count: count) }
  end

  private

  def chunk_row(chunk)
    ChunkRow.new(post_title: chunk.post_title, post_url: chunk.post_url, snippet: snippet(chunk),
                 retrievals_count: chunk.retrievals_count, last_retrieved_at: chunk.last_retrieved_at)
  end

  def snippet(chunk)
    chunk.content.delete_prefix(chunk.post_title).squish.truncate(SNIPPET_LENGTH)
  end
end
