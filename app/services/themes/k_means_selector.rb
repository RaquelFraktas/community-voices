module Themes
  # Runs k-means for every k in a range and keeps the k with the best silhouette score: the one whose points
  # sit closest to their own cluster and farthest from the next one. A fixed seed makes runs reproducible.
  class KMeansSelector
    K_RANGE = (3..8)
    RANDOM_SEED = 42
    MAX_ITERATIONS = 300

    Result = Data.define(:k, :labels, :centroids, :silhouette_score)

    attr_reader :random_seed

    def initialize(k_range: K_RANGE, random_seed: RANDOM_SEED)
      @k_range = k_range
      @random_seed = random_seed
    end

    def select(vectors)
      matrix = Numo::DFloat.cast(vectors)
      candidates = candidate_ks(matrix.shape.first)
      raise ArgumentError, "Need at least #{@k_range.min + 1} vectors to cluster, got #{vectors.size}" if candidates.empty?

      candidates.map { |k| cluster(matrix, k) }.max_by { |result| [ result.silhouette_score, -result.k ] }
    end

    private

    def candidate_ks(vector_count)
      @k_range.select { |k| k < vector_count }
    end

    def cluster(matrix, k)
      k_means = Rumale::Clustering::KMeans.new(n_clusters: k, max_iter: MAX_ITERATIONS, random_seed: random_seed)
      labels = k_means.fit_predict(matrix)
      Result.new(k: k, labels: labels.to_a, centroids: k_means.cluster_centers.to_a,
                 silhouette_score: silhouette(matrix, labels))
    end

    def silhouette(matrix, labels)
      return -1.0 if labels.to_a.uniq.size < 2

      Rumale::EvaluationMeasure::SilhouetteScore.new.score(matrix, labels)
    end
  end
end
