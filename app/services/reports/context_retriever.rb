module Reports
  # Searches the week's chunks once per facet query.
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

    def initialize(search: Search::SimilarChunks.new, facets: DEFAULT_FACETS,
                   matches_per_facet: MATCHES_PER_FACET, max_entries: MAX_ENTRIES)
      @search = search
      @facets = facets
      @matches_per_facet = matches_per_facet
      @max_entries = max_entries
    end

    def retrieve(week)
      numbered_result(select_interleaved(@facets.map { |facet| candidates_for(facet, week) }, @max_entries))
    end

    private

    def candidates_for(facet, week)
      @search.call(facet, limit: @matches_per_facet, since: week.starts_at, before: week.ends_before)
             .map { |match| Candidate.new(query_label: facet, chunk: match.chunk, distance: match.distance) }
    end
  end
end
