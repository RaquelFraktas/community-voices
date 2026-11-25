module ChunkFactory
  def create_chunk(post: create_post, position: 0, content: "#{post.title}\n\nSome content", embedded: true)
    post.chunks.create!(
      position: position, content: content, content_digest: Chunk.digest(content),
      embedding: (Embeddings::FakeClient.new.embed_documents([ content ]).first if embedded)
    )
  end

  def retrieval_attributes_for(chunk, rank: 1, query_label: "new releases and upgrades", distance: 0.2)
    {
      chunk_id: chunk.id, content_snapshot: chunk.content, post_title_snapshot: chunk.post.title,
      post_url_snapshot: chunk.post.url, query_label: query_label, rank: rank, distance: distance
    }
  end
end

RSpec.configure { |config| config.include ChunkFactory }
