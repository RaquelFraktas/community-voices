module Themes
  # Builds a week's themes: clusters the window's chunks, names the clusters, and lays them out in 2D.
  class Builder
    EXAMPLES_PER_CLUSTER = 5
    SNIPPET_LENGTH = 200

    def initialize(clusterer: Clusterer.new, labeler: Themes.labeler, projector: Projector.new)
      @clusterer = clusterer
      @labeler = labeler
      @projector = projector
    end

    def self.latest_or_build(week)
      Clustering.latest_for(week) || new.build(week)
    end

    def build(week)
      Clustering.transaction do
        clustering = @clusterer.cluster(week)
        label(clustering)
        @projector.project(clustering)
      end
    end

    private

    def label(clustering)
      descriptions = clustering.clusters.includes(memberships: { chunk: :post }).to_h do |cluster|
        [ cluster, describe(cluster) ]
      end
      @labeler.label(descriptions, all_titles: descriptions.values.flat_map(&:titles))
              .each { |cluster, label| cluster.update!(label: label) }
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
