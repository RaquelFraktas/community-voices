require "rails_helper"

RSpec.describe Embeddings::FakeClient do
  subject(:client) { described_class.new }

  it "returns one unit vector of the configured dimensions per document" do
    vectors = client.embed_documents([ "first", "second" ])

    expect(vectors.size).to eq(2)
    expect(vectors).to all(have_attributes(size: Embeddings::DIMENSIONS))
    expect(vectors.map { |values| Math.sqrt(values.sum { |value| value * value }) }).to all(be_within(1e-9).of(1.0))
  end

  it "always gives the same text the same vector" do
    expect(client.embed_query("rails upgrade")).to eq(described_class.new.embed_documents([ "rails upgrade" ]).first)
  end

  it "gives different texts different vectors" do
    expect(client.embed_query("rails upgrade")).not_to eq(client.embed_query("deployment"))
  end
end

RSpec.describe Embeddings do
  it "uses the fake client in tests" do
    expect(described_class.client).to be_a(Embeddings::FakeClient)
  end
end
