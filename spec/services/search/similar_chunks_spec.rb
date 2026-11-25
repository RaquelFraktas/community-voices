require "rails_helper"

RSpec.describe Search::SimilarChunks do
  subject(:search) { described_class.new(client: client) }

  let(:client) { Embeddings::FakeClient.new }

  def create_embedded_chunk(content, posted_at: 1.day.ago, embedded: true)
    post = create_post(title: "About #{content}", posted_at: posted_at)
    post.chunks.create!(
      position: 0, content: content, content_digest: Chunk.digest(content),
      embedding: (client.embed_documents([ content ]).first if embedded)
    )
  end

  def blend(first, second, weight)
    first_vector = client.embed_query(first)
    second_vector = client.embed_query(second)
    first_vector.zip(second_vector).map { |a, b| (a * weight) + (b * (1 - weight)) }
  end

  it "ranks chunks by cosine distance to the query, nearest first" do
    exact = create_embedded_chunk("upgrading to Rails 8")
    close = create_embedded_chunk("upgrading close")
    close.update!(embedding: blend("upgrading to Rails 8", "noise", 0.8))
    far = create_embedded_chunk("kamal deploy")

    matches = search.call("upgrading to Rails 8")

    expect(matches.map(&:chunk)).to eq([ exact, close, far ])
    expect(matches.map(&:distance)).to eq(matches.map(&:distance).sort)
  end

  it "reports a distance of zero for an identical vector" do
    create_embedded_chunk("upgrading to Rails 8")

    expect(search.call("upgrading to Rails 8").first.distance).to be_within(1e-6).of(0)
  end

  it "returns at most the requested number of matches" do
    4.times { |i| create_embedded_chunk("chunk #{i}") }

    expect(search.call("chunk 0", limit: 2).size).to eq(2)
  end

  it "returns five matches by default" do
    7.times { |i| create_embedded_chunk("chunk #{i}") }

    expect(search.call("chunk 0").size).to eq(5)
  end

  it "only considers posts published since the given time" do
    recent = create_embedded_chunk("recent", posted_at: 2.days.ago)
    create_embedded_chunk("old", posted_at: 10.days.ago)

    expect(search.call("old", since: 7.days.ago).map(&:chunk)).to eq([ recent ])
  end

  it "only considers posts published before the given time" do
    create_embedded_chunk("recent", posted_at: 2.days.ago)
    old = create_embedded_chunk("old", posted_at: 10.days.ago)

    expect(search.call("recent", before: 7.days.ago).map(&:chunk)).to eq([ old ])
  end

  context "when many closer chunks fall outside the time window" do
    let(:target_week) { 3.weeks.ago.beginning_of_week..3.weeks.ago.end_of_week }
    let(:query) { "rails upgrade" }

    before do
      create_weeks_of_chunks(weeks: 6, near_query_per_week: 12)
      plan_like_a_large_table
    end

    # On a table this small Postgres would filter by date and sort exactly. With many weeks ingested it
    # walks the HNSW index instead, which is the path that needs the iterative scan.
    def plan_like_a_large_table
      Chunk.connection.execute("SET LOCAL enable_seqscan = off")
      Chunk.connection.execute("SET LOCAL enable_sort = off")
      Chunk.connection.execute("SET LOCAL hnsw.ef_search = 10")
    end

    def create_weeks_of_chunks(weeks:, near_query_per_week:)
      weeks.times do |weeks_ago|
        posted_at = weeks_ago.weeks.ago.beginning_of_week + 1.day
        in_target = target_week.cover?(posted_at)
        near_query_per_week.times do |i|
          chunk = create_embedded_chunk("week #{weeks_ago} chunk #{i}", posted_at: posted_at)
          chunk.update!(embedding: blend(query, "week #{weeks_ago} chunk #{i}", in_target ? 0.3 : 0.9))
        end
      end
    end

    it "still returns the requested number of matches, all from the window" do
      matches = search.call(query, limit: 8, since: target_week.begin, before: target_week.end)

      expect(matches.size).to eq(8)
      expect(matches.map { |match| match.post.posted_at }).to all(be_between(target_week.begin, target_week.end))
      expect(matches.map(&:distance)).to eq(matches.map(&:distance).sort)
    end
  end

  it "skips chunks that are not embedded yet" do
    create_embedded_chunk("pending", embedded: false)

    expect(search.call("pending")).to be_empty
  end

  it "exposes each match's post and content" do
    create_embedded_chunk("upgrading to Rails 8")

    match = search.call("upgrading to Rails 8").first

    expect(match.post.title).to eq("About upgrading to Rails 8")
    expect(match.content).to eq("upgrading to Rails 8")
  end
end
