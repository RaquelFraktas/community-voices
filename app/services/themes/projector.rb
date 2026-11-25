module Themes
  # Flattens the clustering's chunk embeddings to 2D with PCA (the two directions along which they vary most)
  # and stores each member's x and y for the embedding map.
  class Projector
    RANDOM_SEED = 42

    def project(clustering)
      memberships = clustering.memberships.includes(:chunk).order(:id).to_a
      coordinates_for(memberships.map { |membership| UnitVectors.unit_length(membership.chunk.embedding) })
        .zip(memberships) { |(x, y), membership| membership.update_columns(x: x, y: y) }
      clustering
    end

    private

    def coordinates_for(vectors)
      pca = Rumale::Decomposition::PCA.new(n_components: 2, random_seed: RANDOM_SEED)
      pca.fit_transform(Numo::DFloat.cast(vectors)).to_a
    end
  end
end
