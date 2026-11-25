module Themes
  # Clusters every embedded chunk posted in the weeks leading up to (and including) a report week, and saves
  # the Clustering with its Clusters and memberships. Labels and 2D positions are filled in afterwards.
  class Clusterer
    WINDOW_WEEKS = 6

    def initialize(selector: KMeansSelector.new, window_weeks: WINDOW_WEEKS)
      @selector = selector
      @window_weeks = window_weeks
    end

    def cluster(week)
      window = window_for(week)
      chunks = embedded_chunks_in(window)
      vectors = chunks.map { |chunk| UnitVectors.unit_length(chunk.embedding) }
      result = @selector.select(vectors)
      save(window, chunks, vectors, result)
    end

    private

    def window_for(week)
      (week.starts_on - (@window_weeks - 1).weeks)..week.ends_on
    end

    def embedded_chunks_in(window)
      Chunk.where.not(embedding: nil).joins(:post)
           .merge(Post.posted_between(window.begin.beginning_of_day, (window.end + 1).beginning_of_day))
           .order(:id).to_a
    end

    def save(window, chunks, vectors, result)
      Clustering.transaction do
        clustering = Clustering.create!(window_start: window.begin, window_end: window.end, k: result.k,
                                        random_seed: @selector.random_seed,
                                        silhouette_score: result.silhouette_score)
        result.centroids.each_with_index do |centroid, position|
          save_cluster(clustering, position, centroid, members_of(position, chunks, vectors, result.labels))
        end
        clustering
      end
    end

    def members_of(position, chunks, vectors, labels)
      labels.each_index.select { |index| labels[index] == position }.map { |index| [ chunks[index], vectors[index] ] }
    end

    def save_cluster(clustering, position, centroid, members)
      cluster = clustering.clusters.create!(position: position, centroid: centroid, size: members.size)
      members.each do |chunk, vector|
        cluster.memberships.create!(chunk: chunk, distance_to_centroid: cosine_distance(vector, centroid))
      end
    end

    def cosine_distance(unit_vector, centroid)
      1.0 - (unit_vector.zip(centroid).sum { |a, b| a * b } / Math.sqrt(centroid.sum { |value| value * value }))
    end
  end
end
