module Seeds
  # Loads a snapshot written by Seeds::Exporter. Every record is upserted on its natural key, so importing
  # twice, or into a database that already has some of the same posts, creates no duplicates.
  class Importer
    Summary = Data.define(:posts, :chunks, :clusterings, :reports) do
      def to_s
        "Seeded #{posts} posts, #{chunks} chunks, #{clusterings} clusterings and #{reports} reports."
      end
    end

    def import(path = DEFAULT_PATH)
      data = JSON.parse(Zlib::GzipReader.open(path, &:read), symbolize_names: true)
      ApplicationRecord.transaction { load_snapshot(data) }
    end

    private

    def load_snapshot(data)
      post_ids = import_posts(data[:posts])
      chunk_ids = import_chunks(data[:chunks], post_ids)
      clustering_ids = data[:clusterings].to_h { |clustering| import_clustering(clustering, chunk_ids) }
      data[:reports].each { |report| import_report(report, chunk_ids, clustering_ids) }
      Summary.new(posts: post_ids.size, chunks: chunk_ids.size, clusterings: clustering_ids.size,
                  reports: data[:reports].size)
    end

    def import_posts(posts)
      upsert(Post, posts, unique_by: %i[source source_id]) if posts.any?
      Post.where(source_id: posts.pluck(:source_id)).to_h { |post| [ [ post.source, post.source_id ], post.id ] }
    end

    def import_chunks(chunks, post_ids)
      rows = chunks.map { |chunk| chunk.except(:post).merge(post_id: post_ids.fetch(post_key(chunk[:post]))) }
      upsert(Chunk, rows, unique_by: %i[post_id position]) if rows.any?
      Chunk.where(post_id: post_ids.values).includes(:post)
           .to_h { |chunk| [ [ chunk.post.source, chunk.post.source_id, chunk.position ], chunk.id ] }
    end

    def import_clustering(data, chunk_ids)
      key = clustering_key(data)
      clustering = Clustering.find_or_initialize_by(key)
      clustering.update!(k: data[:k], silhouette_score: data[:silhouette_score])
      data[:clusters].each { |cluster| import_cluster(clustering, cluster, chunk_ids) }
      [ key, clustering.id ]
    end

    def import_cluster(clustering, data, chunk_ids)
      cluster = clustering.clusters.find_or_initialize_by(position: data[:position])
      cluster.update!(data.slice(:label, :centroid, :size))
      rows = data[:memberships].map do |membership|
        membership.except(:chunk).merge(cluster_id: cluster.id, chunk_id: chunk_ids.fetch(chunk_key(membership[:chunk])))
      end
      upsert(ClusterMembership, rows, unique_by: %i[cluster_id chunk_id]) if rows.any?
    end

    def import_report(data, chunk_ids, clustering_ids)
      report = Report.find_or_initialize_by(week_of: data[:week_of], variant: data[:variant], created_at: data[:created_at])
      report.update!(data.except(:week_of, :variant, :created_at, :clustering, :retrievals)
                         .merge(clustering_id: data[:clustering] && clustering_ids.fetch(clustering_key(data[:clustering]))))
      rows = data[:retrievals].map do |retrieval|
        retrieval.except(:chunk).merge(report_id: report.id, chunk_id: retrieval[:chunk] && chunk_ids[chunk_key(retrieval[:chunk])])
      end
      upsert(Retrieval, rows, unique_by: %i[report_id rank]) if rows.any?
    end

    def upsert(model, rows, unique_by:)
      model.upsert_all(rows, unique_by: unique_by, record_timestamps: true)
    end

    def post_key(data)
      [ data[:source], data[:source_id] ]
    end

    def chunk_key(data)
      [ data[:source], data[:source_id], data[:position] ]
    end

    def clustering_key(data)
      { window_start: Date.iso8601(data[:window_start].to_s), window_end: Date.iso8601(data[:window_end].to_s),
        random_seed: data[:random_seed], created_at: Time.iso8601(data[:created_at]) }
    end
  end
end
