require "rails_helper"

RSpec.describe Themes::KMeansSelector do
  subject(:selector) { described_class.new }

  [ 3, 4, 5 ].each do |group_count|
    it "finds #{group_count} well-separated groups" do
      points = separated_groups(groups: group_count, per_group: 8, seed: group_count)

      result = selector.select(points.map { |point| point[:vector] })

      expect(result.k).to eq(group_count)
      expect(same_partition?(result.labels, points.map { |point| point[:group] })).to be(true)
    end
  end

  it "returns a centroid per cluster and a high silhouette score for clean groups" do
    result = selector.select(separated_groups(groups: 4, per_group: 6).map { |point| point[:vector] })

    expect(result.centroids.size).to eq(4)
    expect(result.centroids).to all(have_attributes(size: Embeddings::DIMENSIONS))
    expect(result.silhouette_score).to be > 0.8
  end

  it "gives the same result for the same seed" do
    vectors = separated_groups(groups: 4, per_group: 6).map { |point| point[:vector] }

    first = described_class.new(random_seed: 11).select(vectors)
    second = described_class.new(random_seed: 11).select(vectors)

    expect(second).to eq(first)
  end

  it "only tries values of k smaller than the number of vectors" do
    vectors = separated_groups(groups: 2, per_group: 2).map { |point| point[:vector] }

    expect(selector.select(vectors).k).to eq(3)
  end

  it "explains when there are too few vectors to cluster" do
    expect { selector.select(Array.new(3) { Array.new(4, 0.1) }) }
      .to raise_error(ArgumentError, /Need at least 4 vectors to cluster, got 3/)
  end
end
