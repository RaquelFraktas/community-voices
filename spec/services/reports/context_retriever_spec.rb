require "rails_helper"

RSpec.describe Reports::ContextRetriever do
  subject(:retriever) do
    described_class.new(search: Search::SimilarChunks.new(client: client), facets: facets,
                        matches_per_facet: 2, max_entries: max_entries)
  end

  let(:client) { Embeddings::FakeClient.new }
  let(:facets) { [ "releases", "deployment" ] }
  let(:max_entries) { 16 }
  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:in_week) { Time.zone.parse("2026-11-18 10:00") }

  # A chunk whose embedding sits close to the given facet (closeness 1.0 is identical).
  def chunk_near(facet, closeness:, posted_at: in_week, title: "#{facet} #{closeness}")
    post = create_post(title: title, posted_at: posted_at)
    chunk = create_chunk(post: post, content: "#{title}\n\nAbout #{facet}.")
    chunk.update!(embedding: blend(client.embed_query(facet), client.embed_query(title), closeness))
    chunk
  end

  def blend(toward, away, weight)
    toward.zip(away).map { |a, b| (a * weight) + (b * (1 - weight)) }
  end

  it "searches each facet and labels every retrieval with the facet that found it" do
    release = chunk_near("releases", closeness: 0.9)
    deployment = chunk_near("deployment", closeness: 0.9)

    attributes = retriever.retrieve(week).retrieval_attributes

    expect(attributes.to_h { |row| [ row[:chunk_id], row[:query_label] ] })
      .to include(release.id => "releases", deployment.id => "deployment")
  end

  it "takes the top matches per facet, nearest first" do
    best = chunk_near("releases", closeness: 0.95)
    second = chunk_near("releases", closeness: 0.9)
    chunk_near("releases", closeness: 0.85)

    release_rows = retriever.retrieve(week).retrieval_attributes.select { |row| row[:query_label] == "releases" }

    expect(release_rows.map { |row| row[:chunk_id] }).to eq([ best.id, second.id ])
  end

  it "interleaves facets by rank, so each facet's best match comes first" do
    releases = [ chunk_near("releases", closeness: 0.95), chunk_near("releases", closeness: 0.9) ]
    deployments = [ chunk_near("deployment", closeness: 0.95), chunk_near("deployment", closeness: 0.9) ]

    chunk_ids = retriever.retrieve(week).retrieval_attributes.map { |row| row[:chunk_id] }

    expect(chunk_ids).to eq([ releases[0].id, deployments[0].id, releases[1].id, deployments[1].id ])
  end

  it "includes a chunk only once when several facets find it" do
    shared = create_chunk(post: create_post(title: "Deploying the new release", posted_at: in_week))
    shared.update!(embedding: blend(client.embed_query("releases"), client.embed_query("deployment"), 0.5))

    attributes = retriever.retrieve(week).retrieval_attributes

    expect(attributes.count { |row| row[:chunk_id] == shared.id }).to eq(1)
    expect(attributes.find { |row| row[:chunk_id] == shared.id }[:query_label]).to eq("releases")
  end

  context "with a small cap" do
    let(:max_entries) { 3 }

    it "caps the total number of entries without dropping a facet" do
      2.times { |i| chunk_near("releases", closeness: 0.9 - (i / 10.0)) }
      2.times { |i| chunk_near("deployment", closeness: 0.9 - (i / 10.0)) }

      labels = retriever.retrieve(week).retrieval_attributes.map { |row| row[:query_label] }

      expect(labels.size).to eq(3)
      expect(labels.uniq).to contain_exactly("releases", "deployment")
    end
  end

  it "only uses posts from the requested week" do
    inside = chunk_near("releases", closeness: 0.5)
    chunk_near("releases", closeness: 0.99, posted_at: Time.zone.parse("2026-11-23 00:00"))
    chunk_near("releases", closeness: 0.99, posted_at: Time.zone.parse("2026-11-15 23:59"))

    expect(retriever.retrieve(week).retrieval_attributes.map { |row| row[:chunk_id] }).to eq([ inside.id ])
  end

  it "numbers the context entries and mirrors them in the retrieval attributes" do
    chunk = chunk_near("releases", closeness: 0.9, title: "Rails 8.1.2 released")

    result = retriever.retrieve(week)

    expect(result.entries.sole).to have_attributes(
      number: 1, post_title: "Rails 8.1.2 released", url: chunk.post.url, posted_at: chunk.post.posted_at,
      content: chunk.content
    )
    expect(result.retrieval_attributes.sole).to include(
      chunk_id: chunk.id, rank: 1, query_label: "releases", content_snapshot: chunk.content,
      post_title_snapshot: "Rails 8.1.2 released", post_url_snapshot: chunk.post.url
    )
    expect(result.retrieval_attributes.sole[:distance]).to be_between(0, 1)
  end

  it "returns an empty result for a week without posts" do
    expect(retriever.retrieve(week)).to eq(Reports::RetrievalResult.empty)
  end

  it "uses the default facets and limits from the milestone brief" do
    expect(described_class::DEFAULT_FACETS.size).to eq(6)
    expect(described_class::MAX_ENTRIES).to eq(16)
  end
end
