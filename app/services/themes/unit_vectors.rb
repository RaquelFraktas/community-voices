module Themes
  # Scales embeddings to length 1 before k-means and PCA, so their Euclidean distances rank chunks the same
  # way as the cosine distance used for search. nomic-embed-text already returns unit vectors; other
  # embedding models may not.
  module UnitVectors
    module_function

    def unit_length(vector)
      length = Math.sqrt(vector.sum { |value| value * value })
      length.zero? ? vector : vector.map { |value| value / length }
    end
  end
end
