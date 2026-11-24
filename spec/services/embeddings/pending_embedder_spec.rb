require "rails_helper"

RSpec.describe Embeddings::PendingEmbedder do
  subject(:embedder) { described_class.new(client: client, batch_size: 2) }

  let(:client) { Embeddings::FakeClient.new }
  let(:post) { create_post }

  def create_chunk(position, embedding: nil)
    content = "Chunk number #{position}"
    post.chunks.create!(position: position, content: content, content_digest: Chunk.digest(content),
                        embedding: embedding)
  end

  it "embeds every chunk that has no embedding yet and returns how many" do
    chunks = Array.new(5) { |position| create_chunk(position) }

    expect(embedder.embed_pending).to eq(5)
    expected_vectors = client.embed_documents(chunks.map(&:content))
    chunks.zip(expected_vectors).each { |chunk, vector| expect(chunk.reload.embedding).to match_vector(vector) }
    expect(Chunk.pending_embedding).to be_empty
  end

  it "sends the chunks to the client in batches" do
    Array.new(5) { |position| create_chunk(position) }
    allow(client).to receive(:embed_documents).and_call_original

    embedder.embed_pending

    expect(client).to have_received(:embed_documents).exactly(3).times
    expect(client).to have_received(:embed_documents).with(an_object_having_attributes(size: 2)).twice
  end

  it "leaves chunks that are already embedded alone" do
    existing_vector = client.embed_query("something else")
    embedded = create_chunk(0, embedding: existing_vector)
    create_chunk(1)

    expect(embedder.embed_pending).to eq(1)
    expect(embedded.reload.embedding).to match_vector(existing_vector)
  end

  it "does nothing when nothing is pending" do
    allow(client).to receive(:embed_documents)

    expect(embedder.embed_pending).to eq(0)
    expect(client).not_to have_received(:embed_documents)
  end

  it "keeps the chunks of earlier batches when a later batch fails" do
    Array.new(3) { |position| create_chunk(position) }
    calls = 0
    allow(client).to receive(:embed_documents).and_wrap_original do |original, texts|
      calls += 1
      raise Embeddings::UnavailableError, "Ollama went away" if calls == 2

      original.call(texts)
    end

    expect { embedder.embed_pending }.to raise_error(Embeddings::UnavailableError)
    expect(Chunk.pending_embedding.count).to eq(1)
  end
end
