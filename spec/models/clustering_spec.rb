require "rails_helper"

RSpec.describe Clustering do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  def create_clustering(window_end: week.ends_on, created_at: Time.current)
    described_class.create!(window_start: window_end - 41.days, window_end: window_end, k: 3, random_seed: 42,
                            created_at: created_at)
  end

  def add_cluster(clustering, position: 0)
    clustering.clusters.create!(position: position, label: "migrations · production", size: 1,
                                centroid: Array.new(Embeddings::DIMENSIONS, 0.1))
  end

  it "finds the newest clustering that ends with a week" do
    create_clustering(created_at: 1.hour.ago)
    newest = create_clustering
    create_clustering(window_end: week.ends_on - 7.days)

    expect(described_class.latest_for(week)).to eq(newest)
  end

  it "lists the six weeks of its window, oldest first" do
    weeks = create_clustering.weeks

    expect(weeks.size).to eq(6)
    expect(weeks.first.starts_on).to eq(Date.new(2026, 10, 12))
    expect(weeks.last).to eq(week)
  end

  it "knows its report week" do
    expect(create_clustering.report_week).to eq(week)
  end

  it "deletes its clusters and memberships with it" do
    clustering = create_clustering
    cluster = add_cluster(clustering)
    cluster.memberships.create!(chunk: create_chunk, distance_to_centroid: 0.1)

    expect { clustering.destroy! }.to change(Cluster, :count).by(-1).and change(ClusterMembership, :count).by(-1)
  end

  it "loses its memberships, not its clusters, when a chunk is deleted" do
    cluster = add_cluster(create_clustering)
    chunk = create_chunk
    cluster.memberships.create!(chunk: chunk, distance_to_centroid: 0.1)

    expect { Chunk.where(id: chunk.id).delete_all }.to change(ClusterMembership, :count).by(-1)
    expect(cluster.reload).to be_persisted
  end

  it "analyzes its clusters' weekly trends from the members' post dates" do
    clustering = create_clustering
    old_theme = add_cluster(clustering, position: 0)
    new_theme = add_cluster(clustering, position: 1)
    old_theme.memberships.create!(chunk: create_chunk(post: create_post(posted_at: week.starts_at - 2.weeks)),
                                  distance_to_centroid: 0.1)
    new_theme.memberships.create!(chunk: create_chunk(post: create_post(posted_at: week.starts_at + 1.day)),
                                  distance_to_centroid: 0.1)

    trends = clustering.trends.index_by(&:cluster_id)

    expect(trends[old_theme.id]).to have_attributes(classification: "fading", this_week_count: 0)
    expect(trends[new_theme.id]).to have_attributes(classification: "new", this_week_count: 1)
    expect(trends[new_theme.id].weekly_counts.keys).to eq(clustering.weeks.map(&:starts_on))
  end

  it "is unlinked from reports when deleted" do
    clustering = create_clustering
    report = Report.create!(week_of: week.starts_on, variant: :rag, clustering: clustering)

    described_class.where(id: clustering.id).delete_all

    expect(report.reload.clustering_id).to be_nil
  end
end
