require "rails_helper"

RSpec.describe Chunking::ChunkSyncer do
  subject(:syncer) { described_class.new(chunker: chunker) }

  let(:chunker) do
    Chunking::PostChunker.new(max_chunk_length: 120, overlap_length: 0, min_content_length: 10, max_chunks_per_post: 5)
  end
  let(:post) { create_post(title: "Title", body: body_of(3)) }
  let(:an_embedding) { Array.new(Embeddings::DIMENSIONS, 0.1) }

  def body_of(paragraph_count, word: "word")
    Array.new(paragraph_count) { |i| Array.new(12, "#{word}#{i}").join(" ") }.join("\n\n")
  end

  def edit_body(new_body)
    post.update!(body: new_body)
    post.reload
  end

  it "creates one chunk per chunk text, in order" do
    tally = syncer.sync(post)

    expect(post.chunks.map(&:position)).to eq([ 0, 1, 2 ])
    expect(post.chunks.map(&:content)).to eq(chunker.chunk(post))
    expect(tally).to have_attributes(posts: 1, created: 3, unchanged: 0, replaced: 0, deleted: 0)
  end

  it "stores the SHA256 digest of each chunk's content" do
    syncer.sync(post)

    expect(post.chunks).to all(satisfy { |chunk| chunk.content_digest == Chunk.digest(chunk.content) })
  end

  it "leaves new chunks waiting for an embedding" do
    syncer.sync(post)

    expect(Chunk.pending_embedding.count).to eq(3)
  end

  it "writes one row per new chunk" do
    post

    expect(count_sql_writes { syncer.sync(post) }).to eq(3)
  end

  context "when the post has not changed" do
    before do
      syncer.sync(post)
      post.chunks.each { |chunk| chunk.update!(embedding: an_embedding) }
      post.reload
    end

    it "makes zero writes on rerun" do
      expect(count_sql_writes { syncer.sync(post) }).to eq(0)
    end

    it "makes zero writes when rerun over every post" do
      expect(count_sql_writes { syncer.sync_all }).to eq(0)
    end

    it "keeps the chunks and their embeddings" do
      expect { syncer.sync(post) }.not_to(change { post.chunks.reload.map(&:attributes) })
    end

    it "reports them as unchanged" do
      expect(syncer.sync(post)).to have_attributes(created: 0, unchanged: 3, replaced: 0, deleted: 0)
    end
  end

  context "when a chunk's content changes" do
    let(:edited_body) { body_of(3).sub("word1", "edited") }

    before do
      syncer.sync(post)
      post.chunks.each { |chunk| chunk.update!(embedding: an_embedding, retrievals_count: 4) }
      edit_body(edited_body)
    end

    it "replaces the changed chunk with a new, unembedded row" do
      original_ids = post.chunks.map(&:id)

      tally = syncer.sync(post)

      replacement = post.chunks.reload.find_by!(position: 1)
      expect(original_ids).not_to include(replacement.id)
      expect(Chunk.exists?(original_ids[1])).to be(false)
      expect(replacement.content).to include("edited")
      expect(replacement.content_digest).to eq(Chunk.digest(replacement.content))
      expect(replacement.embedding).to be_nil
      expect(replacement.retrievals_count).to eq(0)
      expect(tally).to have_attributes(unchanged: 2, replaced: 1)
    end

    it "keeps the rows, embeddings and retrieval counts of the unchanged chunks" do
      unchanged_before = post.chunks.reject { |chunk| chunk.position == 1 }.map(&:attributes)

      syncer.sync(post)

      expect(post.chunks.reload.reject { |chunk| chunk.position == 1 }.map(&:attributes)).to eq(unchanged_before)
    end

    it "keeps the embeddings of the unchanged chunks" do
      syncer.sync(post)

      expect(post.chunks.reload.where.not(position: 1).map(&:embedding)).to all(eq(an_embedding))
    end
  end

  it "deletes chunks whose positions no longer exist" do
    syncer.sync(post)
    edit_body(body_of(1))

    tally = syncer.sync(post)

    expect(post.chunks.reload.map(&:position)).to eq([ 0 ])
    expect(tally).to have_attributes(unchanged: 1, deleted: 2)
  end

  it "deletes every chunk when the post becomes too short to chunk" do
    syncer.sync(post)
    edit_body("Thanks!")

    expect(syncer.sync(post)).to have_attributes(deleted: 3)
    expect(post.chunks.reload).to be_empty
  end

  it "adds chunks when the post grows" do
    syncer.sync(post)
    edit_body(body_of(4))

    expect(syncer.sync(post)).to have_attributes(unchanged: 3, created: 1)
  end

  describe "#sync_all" do
    it "syncs every post and adds up the tallies" do
      post
      create_post(body: body_of(2, word: "other"))

      tally = syncer.sync_all

      expect(tally).to have_attributes(posts: 2, created: 5)
      expect(tally.to_s).to eq("Synced chunks for 2 posts: 5 created, 0 unchanged, 0 replaced, 0 deleted.")
    end
  end
end
