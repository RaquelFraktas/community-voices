require "rails_helper"

RSpec.describe Themes::Clusterer do
  subject(:clusterer) { described_class.new }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:points) { separated_groups(groups: 3, per_group: 5) }
  let!(:chunks_by_group) do
    points.each_with_index.map do |point, index|
      posted_at = week.starts_at - (index % 6).weeks + 1.day
      chunk = create_chunk(post: create_post(title: "Post #{index}", posted_at: posted_at))
      chunk.update!(embedding: point[:vector])
      [ point[:group], chunk ]
    end
  end

  it "saves a clustering covering the six weeks ending with the report week" do
    clustering = clusterer.cluster(week)

    expect(clustering).to have_attributes(window_start: Date.new(2026, 10, 12), window_end: Date.new(2026, 11, 22),
                                          k: 3, random_seed: Themes::KMeansSelector::RANDOM_SEED)
    expect(clustering.silhouette_score).to be > 0.8
  end

  it "puts the chunks of each synthetic group together" do
    clustering = clusterer.cluster(week)

    found = clustering.clusters.map { |cluster| cluster.chunks.map(&:id).sort }
    expected = chunks_by_group.group_by(&:first).values.map { |pairs| pairs.map { |_group, chunk| chunk.id }.sort }
    expect(found).to match_array(expected)
  end

  it "records each cluster's size, centroid and every member's cosine distance to it" do
    clustering = clusterer.cluster(week)

    expect(clustering.clusters.map(&:size)).to all(eq(5))
    expect(clustering.clusters.map { |cluster| cluster.centroid.size }).to all(eq(Embeddings::DIMENSIONS))
    expect(ClusterMembership.pluck(:distance_to_centroid)).to all(be_between(0, 0.05))
  end

  it "ignores chunks outside the window and chunks not embedded yet" do
    create_chunk(post: create_post(posted_at: week.ends_before)).update!(embedding: points.first[:vector])
    create_chunk(post: create_post(posted_at: week.starts_at - 6.weeks)).update!(embedding: points.first[:vector])
    create_chunk(post: create_post(posted_at: week.starts_at + 1.day), embedded: false)

    expect(clusterer.cluster(week).memberships.count).to eq(15)
  end

  it "gives the same clusters when run again" do
    first = clusterer.cluster(week).clusters.map { |cluster| cluster.chunks.map(&:id).sort }
    second = clusterer.cluster(week).clusters.map { |cluster| cluster.chunks.map(&:id).sort }

    expect(second).to eq(first)
  end

  it "can use a shorter window" do
    clustering = described_class.new(window_weeks: 2, selector: Themes::KMeansSelector.new(k_range: 2..3))
                                .cluster(week)

    expect(clustering.window_start).to eq(Date.new(2026, 11, 9))
  end
end
