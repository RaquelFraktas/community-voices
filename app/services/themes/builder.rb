module Themes
  # Builds a week's themes: clusters the window's chunks, gives them TF-IDF labels and lays them out in 2D in
  # one transaction, then asks the configured labeler for better names. Labeling runs after the commit, so a
  # slow model never holds the transaction open and a labeling failure keeps the TF-IDF labels.
  class Builder
    EXAMPLES_PER_CLUSTER = 5
    SNIPPET_LENGTH = 200

    def initialize(clusterer: Clusterer.new, labeler: Themes.labeler, fallback_labeler: Labeler.new,
                   projector: Projector.new)
      @clusterer = clusterer
      @labeler = labeler
      @fallback_labeler = fallback_labeler
      @projector = projector
    end

    def self.latest_or_build(week)
      Clustering.latest_for(week) || new.build(week)
    end

    def build(week)
      clustering, descriptions = persist(week)
      relabel(descriptions)
      clustering
    end

    private

    def persist(week)
      Clustering.transaction do
        clustering = @clusterer.cluster(week)
        descriptions = describe_clusters(clustering)
        apply_labels(@fallback_labeler, descriptions)
        @projector.project(clustering)
        [ clustering, descriptions ]
      end
    end

    def relabel(descriptions)
      apply_labels(@labeler, descriptions)
    rescue StandardError => error
      Rails.logger.warn("[Themes] Labeling failed, keeping TF-IDF labels: #{error.class}: #{error.message}")
    end

    def apply_labels(labeler, descriptions)
      labeler.label(descriptions, all_titles: descriptions.values.flat_map(&:titles))
             .each { |cluster, label| cluster.update!(label: label) }
    end

    def describe_clusters(clustering)
      clustering.clusters.includes(memberships: { chunk: :post }).to_h { |cluster| [ cluster, describe(cluster) ] }
    end

    def describe(cluster)
      chunks = cluster.memberships.map(&:chunk)
      ClusterDescription.new(titles: chunks.map { |chunk| chunk.post.title },
                             examples: chunks.first(EXAMPLES_PER_CLUSTER).map { |chunk| example_from(chunk) })
    end

    def example_from(chunk)
      ClusterExample.new(title: chunk.post.title,
                         snippet: chunk.content.delete_prefix(chunk.post.title).squish.truncate(SNIPPET_LENGTH))
    end
  end
end
