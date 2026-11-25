module Seeds
  # Writes the last few weeks of data to gzipped JSON. Records refer to each other by natural keys rather than
  # database ids, so the snapshot loads into any database.
  class Exporter
    POST_FIELDS = %i[source source_id title body author url posted_at reply_count].freeze
    REPORT_FIELDS = %i[week_of variant status llm_model prompt body error_message generation_seconds].freeze
    RETRIEVAL_FIELDS = %i[content_snapshot post_title_snapshot post_url_snapshot query_label rank distance].freeze

    def initialize(last_week: Week.most_recent_complete, window_weeks: WINDOW_WEEKS)
      @last_week = last_week
      @window_weeks = window_weeks
    end

    def export(path = DEFAULT_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      Zlib::GzipWriter.open(path) { |gzip| gzip.write(JSON.generate(snapshot)) }
      path
    end

    def snapshot
      reports = exported_reports
      { version: FORMAT_VERSION, posts: posts.map { |post| post_json(post) }, chunks: chunks.map { |chunk| chunk_json(chunk) },
        clusterings: exported_clusterings(reports).map { |clustering| clustering_json(clustering) },
        reports: reports.map { |report| report_json(report) } }
    end

    private

    def window_start
      @last_week.starts_on - (@window_weeks - 1).weeks
    end

    def posts
      @posts ||= Post.posted_since(window_start.beginning_of_day).order(:source, :source_id).to_a
    end

    def chunks
      Chunk.where(post: posts).includes(:post).sort_by { |chunk| chunk_key(chunk).values }
    end

    def exported_reports
      (window_start..@last_week.starts_on).step(7).flat_map do |starts_on|
        comparison = Reports::Comparison.for(Week.new(starts_on))
        comparison.complete? ? comparison.reports : []
      end
    end

    def exported_clusterings(reports)
      latest_per_week = (window_start..@last_week.starts_on).step(7).filter_map { |date| Clustering.latest_for(Week.new(date)) }
      (latest_per_week + reports.filter_map(&:clustering)).uniq.sort_by(&:created_at)
    end

    def post_json(post)
      attributes_of(post, *POST_FIELDS).merge(posted_at: timestamp(post.posted_at))
    end

    def chunk_json(chunk)
      { post: post_key(chunk.post),
        **attributes_of(chunk, :position, :content, :content_digest, :embedding, :retrievals_count) }
    end

    def clustering_json(clustering)
      { **clustering_key(clustering), k: clustering.k, silhouette_score: clustering.silhouette_score,
        clusters: clustering.clusters.includes(memberships: { chunk: :post }).map { |cluster| cluster_json(cluster) } }
    end

    def cluster_json(cluster)
      memberships = cluster.memberships.sort_by { |membership| chunk_key(membership.chunk).values }
      { **attributes_of(cluster, :position, :label, :centroid, :size),
        memberships: memberships.map do |membership|
          { chunk: chunk_key(membership.chunk), **attributes_of(membership, :distance_to_centroid, :x, :y) }
        end }
    end

    def report_json(report)
      { **attributes_of(report, *REPORT_FIELDS), created_at: timestamp(report.created_at),
        clustering: (clustering_key(report.clustering) if report.clustering),
        retrievals: report.retrievals.includes(chunk: :post).map { |retrieval| retrieval_json(retrieval) } }
    end

    def retrieval_json(retrieval)
      { chunk: (chunk_key(retrieval.chunk) if retrieval.chunk), **attributes_of(retrieval, *RETRIEVAL_FIELDS),
        created_at: timestamp(retrieval.created_at) }
    end

    def post_key(post)
      { source: post.source, source_id: post.source_id }
    end

    def chunk_key(chunk)
      { **post_key(chunk.post), position: chunk.position }
    end

    def clustering_key(clustering)
      { window_start: clustering.window_start, window_end: clustering.window_end, random_seed: clustering.random_seed,
        created_at: timestamp(clustering.created_at) }
    end

    def attributes_of(record, *fields)
      record.slice(*fields).symbolize_keys
    end

    def timestamp(time)
      time.utc.iso8601(6)
    end
  end
end
