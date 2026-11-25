module Chunking
  class ChunkSyncer
    def initialize(chunker: PostChunker.new)
      @chunker = chunker
    end

    def sync_all(posts = Post.all)
      posts.includes(:chunks).find_each.sum(SyncTally.zero) { |post| sync(post) }
    end

    def sync(post)
      texts = @chunker.chunk(post)
      existing = post.chunks.index_by(&:position)

      Chunk.transaction do
        sync_positions(post, texts, existing) + delete_beyond(texts.size, existing.values)
      end
    end

    private

    def sync_positions(post, texts, existing)
      texts.each_with_index.sum(SyncTally.new(posts: 1)) do |text, position|
        sync_position(post, existing[position], position, text)
      end
    end

    def sync_position(post, chunk, position, text)
      digest = Chunk.digest(text)
      return create_chunk(post, position, text, digest) if chunk.nil?
      return SyncTally.new(unchanged: 1) if chunk.content_digest == digest

      replace_chunk(chunk, text, digest)
    end

    def create_chunk(post, position, text, digest)
      insert_chunk(post, position, text, digest)
      SyncTally.new(created: 1)
    end

    def replace_chunk(chunk, text, digest)
      chunk.delete
      insert_chunk(chunk.post, chunk.position, text, digest)
      SyncTally.new(replaced: 1)
    end

    def insert_chunk(post, position, text, digest)
      post.chunks.create!(position: position, content: text, content_digest: digest)
    end

    def delete_beyond(chunk_count, chunks)
      stale_ids = chunks.select { |chunk| chunk.position >= chunk_count }.map(&:id)
      Chunk.where(id: stale_ids).delete_all if stale_ids.any?
      SyncTally.new(deleted: stale_ids.size)
    end
  end
end
