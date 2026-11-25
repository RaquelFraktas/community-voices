module Themes
  # The JSON behind the embedding map: one entry per cluster (label, color, trend) and one point per chunk.
  class EmbeddingMapSerializer
    def initialize(clustering)
      @clustering = clustering
    end

    def as_json(*)
      { week_of: @clustering.report_week.to_param, window_start: @clustering.window_start.iso8601,
        window_end: @clustering.window_end.iso8601, clusters: clusters, points: points }
    end

    private

    def clusters
      trends = @clustering.trends.index_by(&:cluster_id)
      @clustering.clusters.map do |cluster|
        trend = trends.fetch(cluster.id)
        { id: cluster.id, label: cluster.label, size: cluster.size, color: Palette.color_for(cluster.position),
          trend: trend.classification, momentum: trend.momentum }
      end
    end

    def points
      report_week = @clustering.report_week
      memberships.map do |membership|
        chunk = membership.chunk
        { x: membership.x, y: membership.y, cluster_id: membership.cluster_id, cluster_label: membership.cluster.label,
          title: chunk.post.title, url: chunk.post.url, posted_on: chunk.post.posted_at.to_date.iso8601,
          retrievals_count: chunk.retrievals_count,
          in_report_week: chunk.post.posted_at.between?(report_week.starts_at, report_week.ends_before) }
      end
    end

    def memberships
      @clustering.memberships.where.not(x: nil).includes(:cluster, chunk: :post).order(:id)
    end
  end
end
