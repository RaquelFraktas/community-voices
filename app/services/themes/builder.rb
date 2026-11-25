module Themes
  # Builds a week's themes: clusters the window's chunks, names the clusters, and lays them out in 2D.
  class Builder
    def initialize(clusterer: Clusterer.new, labeler: Labeler.new, projector: Projector.new)
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
      titles = clustering.clusters.includes(chunks: :post).to_h do |cluster|
        [ cluster, cluster.chunks.map { |chunk| chunk.post.title } ]
      end
      @labeler.label(titles, all_titles: titles.values.flatten)
              .each { |cluster, label| cluster.update!(label: label) }
    end
  end
end
