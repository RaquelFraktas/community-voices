module Reports
  # Searches the week's chunks once per facet, then interleaves the results by rank so every facet is
  # represented before the cap cuts the list short.
  class ContextRetriever < Retriever
    DEFAULT_FACETS = [
      "new releases and upgrades",
      "bugs, errors, and help requests",
      "deployment and infrastructure",
      "gems and libraries",
      "architecture and best practices",
      "jobs, community, and events"
    ].freeze
    MATCHES_PER_FACET = 4
    MAX_ENTRIES = 16

    Candidate = Data.define(:query_label, :match)

    def initialize(search: Search::SimilarChunks.new, facets: DEFAULT_FACETS,
                   matches_per_facet: MATCHES_PER_FACET, max_entries: MAX_ENTRIES)
      @search = search
      @facets = facets
      @matches_per_facet = matches_per_facet
      @max_entries = max_entries
    end

    def retrieve(week)
      candidates = interleave_by_rank(@facets.map { |facet| candidates_for(facet, week) })
      selected = candidates.uniq { |candidate| candidate.match.chunk.id }.first(@max_entries)
      result_for(selected)
    end

    private

    def candidates_for(facet, week)
      @search.call(facet, limit: @matches_per_facet, since: week.starts_at, before: week.ends_before)
             .map { |match| Candidate.new(query_label: facet, match: match) }
    end

    def interleave_by_rank(lists)
      longest = lists.map(&:size).max.to_i
      (0...longest).flat_map { |rank| lists.filter_map { |list| list[rank] } }
    end

    def result_for(candidates)
      numbered = candidates.each.with_index(1).to_a
      RetrievalResult.new(
        entries: numbered.map { |candidate, number| entry_for(candidate.match, number) },
        retrieval_attributes: numbered.map { |candidate, number| retrieval_attributes_for(candidate, number) }
      )
    end

    def entry_for(match, number)
      ContextEntry.new(number: number, post_title: match.post.title, url: match.post.url,
                       posted_at: match.post.posted_at, content: match.content)
    end

    def retrieval_attributes_for(candidate, number)
      match = candidate.match
      {
        chunk_id: match.chunk.id, content_snapshot: match.content, post_title_snapshot: match.post.title,
        post_url_snapshot: match.post.url, query_label: candidate.query_label, rank: number,
        distance: match.distance
      }
    end
  end
end
