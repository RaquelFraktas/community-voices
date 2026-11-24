module Chunking
  class PostChunker
    MAX_CHUNK_LENGTH = 1_500
    OVERLAP_LENGTH = 150
    MIN_CONTENT_LENGTH = 20
    MAX_CHUNKS_PER_POST = 8
    TITLE_SEPARATOR = "\n\n".freeze

    def initialize(max_chunk_length: MAX_CHUNK_LENGTH, overlap_length: OVERLAP_LENGTH,
                   min_content_length: MIN_CONTENT_LENGTH, max_chunks_per_post: MAX_CHUNKS_PER_POST)
      @max_chunk_length = max_chunk_length
      @overlap_length = overlap_length
      @min_content_length = min_content_length
      @max_chunks_per_post = max_chunks_per_post
    end

    def chunk(post)
      body = post.body.to_s.strip
      return [] if body.length < @min_content_length

      heading = post.title + TITLE_SEPARATOR
      splitter_for(heading).split(body).first(@max_chunks_per_post).map { |text| heading + text }
    end

    private

    def splitter_for(heading)
      TextSplitter.new(max_length: @max_chunk_length - heading.length, overlap_length: @overlap_length)
    end
  end
end
