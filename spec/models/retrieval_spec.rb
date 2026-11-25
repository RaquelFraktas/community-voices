require "rails_helper"

RSpec.describe Retrieval do
  let(:report) { Report.create!(week_of: Date.new(2026, 11, 16), variant: :rag) }
  let(:post) { create_post(title: "Rails 8.1 upgrade", body: "First paragraph.\n\nSecond paragraph.") }
  let(:chunk) { create_chunk(post: post) }

  def create_retrieval(for_chunk: chunk, rank: 1)
    report.retrievals.create!(retrieval_attributes_for(for_chunk, rank: rank))
  end

  describe "counter cache" do
    it "increments the chunk's retrievals_count when a retrieval is created" do
      expect { create_retrieval }.to change { chunk.reload.retrievals_count }.from(0).to(1)
    end

    it "counts every retrieval of the same chunk" do
      create_retrieval(rank: 1)
      Report.create!(week_of: report.week_of, variant: :rag).retrievals.create!(retrieval_attributes_for(chunk))

      expect(chunk.reload.retrievals_count).to eq(2)
    end

    it "still works for retrievals whose chunk is gone" do
      retrieval = create_retrieval
      Chunk.where(id: chunk.id).delete_all

      expect { retrieval.reload.update!(rank: 2) }.not_to raise_error
      expect { retrieval.destroy! }.not_to raise_error
    end
  end

  describe "history" do
    it "survives a chunk replacement: chunk_id becomes null and the snapshot is intact" do
      Chunking::ChunkSyncer.new.sync(post)
      original = post.chunks.reload.first
      retrieval = create_retrieval(for_chunk: original)

      post.update!(body: "First paragraph, edited.\n\nSecond paragraph.")
      Chunking::ChunkSyncer.new.sync(post.reload)

      retrieval.reload
      expect(retrieval.chunk_id).to be_nil
      expect(retrieval.content_snapshot).to eq(original.content)
      expect(retrieval.post_title_snapshot).to eq("Rails 8.1 upgrade")
      expect(retrieval.post_url_snapshot).to eq(post.url)
    end

    it "survives deletion of the post" do
      retrieval = create_retrieval
      post.destroy!

      expect(retrieval.reload).to have_attributes(chunk_id: nil, post_title_snapshot: "Rails 8.1 upgrade")
    end

    it "is deleted with its report" do
      create_retrieval

      expect { Report.where(id: report.id).delete_all }.to change(described_class, :count).by(-1)
    end
  end

  it "allows one retrieval per rank within a report" do
    create_retrieval(rank: 1)

    expect { create_retrieval(rank: 1) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
