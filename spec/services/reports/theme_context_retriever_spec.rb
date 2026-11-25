require "rails_helper"

RSpec.describe Reports::ThemeContextRetriever do
  subject(:retriever) { described_class.new(clustering_for: ->(_week) { clustering }, max_entries: max_entries) }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:max_entries) { 16 }
  let(:clustering) do
    Clustering.create!(window_start: week.starts_on - 5.weeks, window_end: week.ends_on, k: 3, random_seed: 42)
  end

  def add_cluster(label, position:)
    clustering.clusters.create!(position: position, label: label, size: 0,
                                centroid: Array.new(Embeddings::DIMENSIONS, 0.1))
  end

  def add_member(cluster, posted_at:, distance:)
    chunk = create_chunk(post: create_post(title: "#{cluster.label} post", posted_at: posted_at),
                         content: "#{cluster.label} at #{distance}")
    cluster.memberships.create!(chunk: chunk, distance_to_centroid: distance)
    chunk
  end

  def this_week(day = 1)
    week.starts_at + day.days
  end

  def weeks_ago(count)
    week.starts_at - count.weeks + 1.day
  end

  let!(:rising) { add_cluster("rising theme", position: 0) }
  let!(:steady) { add_cluster("steady theme", position: 1) }
  let!(:brand_new) { add_cluster("new theme", position: 2) }

  before do
    add_member(rising, posted_at: weeks_ago(1), distance: 0.3)
    3.times { |i| add_member(rising, posted_at: this_week, distance: 0.1 + (i / 10.0)) }
    2.times { |i| add_member(steady, posted_at: weeks_ago(1), distance: 0.2 + (i / 10.0)) }
    add_member(steady, posted_at: this_week, distance: 0.25)
    add_member(brand_new, posted_at: this_week, distance: 0.15)
  end

  it "orders themes by momentum, with new themes first, and interleaves their closest chunks" do
    labels = retriever.retrieve(week).retrieval_attributes.map { |row| row[:query_label] }

    expect(labels).to eq([ "new theme", "rising theme", "steady theme", "rising theme", "rising theme" ])
  end

  it "takes each theme's chunks from the report week, closest to the centroid first" do
    rows = retriever.retrieve(week).retrieval_attributes.select { |row| row[:query_label] == "rising theme" }

    expect(rows.map { |row| row[:distance] }).to match([ 0.1, 0.2, 0.3 ].map { |distance| be_within(1e-9).of(distance) })
    expect(rows.map { |row| Chunk.find(row[:chunk_id]).post.posted_at }).to all(be >= week.starts_at)
  end

  it "only uses chunks posted in the report week" do
    chunk_ids = retriever.retrieve(week).retrieval_attributes.map { |row| row[:chunk_id] }

    expect(Chunk.where(id: chunk_ids).joins(:post).where(posts: { posted_at: ...week.starts_at })).to be_empty
    expect(Chunk.where(id: chunk_ids).joins(:post).where(posts: { posted_at: week.ends_before.. })).to be_empty
  end

  it "skips themes with no chunks in the report week" do
    faded = add_cluster("faded theme", position: 3)
    add_member(faded, posted_at: weeks_ago(2), distance: 0.1)

    expect(retriever.retrieve(week).retrieval_attributes.map { |row| row[:query_label] }).not_to include("faded theme")
  end

  context "with a small cap" do
    let(:max_entries) { 2 }

    it "caps the entries, keeping the themes with the most momentum" do
      labels = retriever.retrieve(week).retrieval_attributes.map { |row| row[:query_label] }

      expect(labels).to eq([ "new theme", "rising theme" ])
    end
  end

  it "numbers the entries [n] and labels each retrieval with its theme" do
    result = retriever.retrieve(week)

    expect(result.entries.map(&:number)).to eq([ 1, 2, 3, 4, 5 ])
    expect(result.retrieval_attributes.map { |row| row[:rank] }).to eq([ 1, 2, 3, 4, 5 ])
    expect(result.entries.first.content).to eq("new theme at 0.15")
  end

  it "returns the trend table and the clustering it used" do
    result = retriever.retrieve(week)

    expect(result.clustering).to eq(clustering)
    expect(result.trends.to_h { |trend| [ trend.label, trend.classification ] })
      .to eq("rising theme" => "rising", "steady theme" => "fading", "new theme" => "new")
  end

  it "builds the week's themes when none exist yet, by default" do
    Clustering.delete_all
    create_themed_chunks(week: week, titles_by_group: [ "Migrations", "ActiveStorage CDN", "Kamal deploys" ])

    expect { described_class.new.retrieve(week) }.to change(Clustering, :count).by(1)
  end
end
