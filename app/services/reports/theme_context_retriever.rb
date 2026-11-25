module Reports
  # Builds context from the week's themes: for every cluster with chunks in the report week, the chunks
  # closest to its centroid, taking clusters with the most momentum first (new themes before all others).
  class ThemeContextRetriever < Retriever
    MATCHES_PER_CLUSTER = 4

    def initialize(clustering_for: Themes::Builder.method(:latest_or_build),
                   matches_per_cluster: MATCHES_PER_CLUSTER, max_entries: MAX_ENTRIES)
      @clustering_for = clustering_for
      @matches_per_cluster = matches_per_cluster
      @max_entries = max_entries
    end

    def retrieve(week)
      clustering = @clustering_for.call(week)
      trends = clustering.trends
      ranked_lists = by_momentum(trends.select { |trend| trend.this_week_count.positive? })
                       .map { |trend| candidates_for(clustering.clusters.find(trend.cluster_id), week) }
      numbered_result(select_interleaved(ranked_lists, @max_entries), trends: trends, clustering: clustering)
    end

    private

    def by_momentum(trends)
      trends.sort_by { |trend| [ -(trend.momentum || Float::INFINITY), -trend.this_week_count, trend.label ] }
    end

    def candidates_for(cluster, week)
      ClusterMembership.where(cluster: cluster).joins(chunk: :post)
                       .merge(Post.posted_between(week.starts_at, week.ends_before))
                       .includes(chunk: :post).order(:distance_to_centroid).limit(@matches_per_cluster)
                       .map do |membership|
        Candidate.new(query_label: cluster.label, chunk: membership.chunk, distance: membership.distance_to_centroid)
      end
    end
  end
end
