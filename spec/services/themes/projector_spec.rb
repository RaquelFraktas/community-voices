require "rails_helper"

RSpec.describe Themes::Projector do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:clustering) do
    create_themed_chunks(week: week, titles_by_group: [ "Migrations", "ActiveStorage CDN", "Kamal deploys" ])
    Themes::Clusterer.new.cluster(week)
  end

  it "gives every membership a 2D position" do
    described_class.new.project(clustering)

    coordinates = ClusterMembership.pluck(:x, :y)
    expect(coordinates.size).to eq(12)
    expect(coordinates.flatten).to all(be_a(Float))
  end

  it "keeps clusters apart in 2D" do
    described_class.new.project(clustering)

    centers = clustering.clusters.map do |cluster|
      points = cluster.memberships.pluck(:x, :y)
      points.transpose.map { |values| values.sum / values.size }
    end
    spreads = clustering.clusters.map { |cluster| cluster.memberships.pluck(:x, :y).flatten.minmax.inject(:-).abs }
    closest_centers = centers.combination(2).map { |a, b| Math.hypot(a[0] - b[0], a[1] - b[1]) }.min
    expect(closest_centers).to be > spreads.max
  end

  it "gives the same positions when run again" do
    described_class.new.project(clustering)
    first = ClusterMembership.order(:id).pluck(:x, :y)

    described_class.new.project(clustering)

    expect(ClusterMembership.order(:id).pluck(:x, :y)).to eq(first)
  end
end
