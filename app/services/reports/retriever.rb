module Reports
  # Interface for building a report's context. Implementations return a Reports::RetrievalResult for a Week.
  # Subclasses gather ranked candidate chunks; this class interleaves, de-duplicates, caps and numbers them.
  class Retriever
    MAX_ENTRIES = 16
    IMPLEMENTATIONS = { "themes" => "Reports::ThemeContextRetriever", "facets" => "Reports::ContextRetriever" }.freeze

    Candidate = Data.define(:query_label, :chunk, :distance)

    def self.configured(name = ENV.fetch("RAG_RETRIEVER", "themes"))
      class_name = IMPLEMENTATIONS.fetch(name) do
        raise ArgumentError, "RAG_RETRIEVER must be one of #{IMPLEMENTATIONS.keys.join(', ')}, got #{name.inspect}"
      end
      class_name.constantize.new
    end

    def retrieve(week)
      raise NotImplementedError, "#{self.class} must implement #retrieve"
    end

    private

    # Takes the best candidate of each list, then the second best of each, and so on, so every list is
    # represented before the cap cuts the result short.
    def select_interleaved(ranked_lists, max_entries)
      longest = ranked_lists.map(&:size).max.to_i
      (0...longest).flat_map { |rank| ranked_lists.filter_map { |list| list[rank] } }
                   .uniq { |candidate| candidate.chunk.id }
                   .first(max_entries)
    end

    def numbered_result(candidates, **extras)
      numbered = candidates.each.with_index(1).to_a
      RetrievalResult.new(
        entries: numbered.map { |candidate, number| entry_for(candidate, number) },
        retrieval_attributes: numbered.map { |candidate, number| retrieval_attributes_for(candidate, number) },
        **extras
      )
    end

    def entry_for(candidate, number)
      post = candidate.chunk.post
      ContextEntry.new(number: number, post_title: post.title, url: post.url, posted_at: post.posted_at,
                       content: candidate.chunk.content)
    end

    def retrieval_attributes_for(candidate, number)
      post = candidate.chunk.post
      {
        chunk_id: candidate.chunk.id, content_snapshot: candidate.chunk.content, post_title_snapshot: post.title,
        post_url_snapshot: post.url, query_label: candidate.query_label, rank: number, distance: candidate.distance
      }
    end
  end
end
