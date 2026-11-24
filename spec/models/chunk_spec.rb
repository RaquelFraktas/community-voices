require "rails_helper"

RSpec.describe Chunk do
  let(:post) { create_post }

  def create_chunk(position: 0, content: "Some content", embedding: nil)
    post.chunks.create!(position: position, content: content, content_digest: Chunk.digest(content),
                        embedding: embedding)
  end

  it "digests content with SHA256" do
    expect(Chunk.digest("hello")).to eq(Digest::SHA256.hexdigest("hello"))
  end

  it "starts with no retrievals" do
    expect(create_chunk.retrievals_count).to eq(0)
  end

  it "lists chunks without an embedding as pending" do
    pending_chunk = create_chunk(position: 0)
    create_chunk(position: 1, embedding: Array.new(Embeddings::DIMENSIONS, 0.1))

    expect(Chunk.pending_embedding).to contain_exactly(pending_chunk)
  end

  it "rejects embeddings with the wrong number of dimensions" do
    expect { create_chunk(embedding: [ 0.1, 0.2 ]) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "allows one chunk per position within a post" do
    create_chunk(position: 0)

    expect { create_chunk(position: 0) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "is deleted together with its post, even when the post is deleted in SQL" do
    create_chunk

    expect { Post.where(id: post.id).delete_all }.to change(Chunk, :count).by(-1)
  end
end
