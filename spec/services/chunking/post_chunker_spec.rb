require "rails_helper"

RSpec.describe Chunking::PostChunker do
  subject(:chunker) do
    described_class.new(max_chunk_length: 200, overlap_length: 30, min_content_length: 20, max_chunks_per_post: 3)
  end

  let(:title) { "Upgrading to Rails 8" }

  def post_with(body)
    Post.new(title: title, body: body)
  end

  def paragraphs(count, words_each: 25)
    Array.new(count) { |i| Array.new(words_each, "p#{i}").join(" ") }.join("\n\n")
  end

  it "turns a short post into one chunk prefixed with its title" do
    chunks = chunker.chunk(post_with("We upgraded last week and it went smoothly."))

    expect(chunks).to eq([ "Upgrading to Rails 8\n\nWe upgraded last week and it went smoothly." ])
  end

  it "prefixes every chunk with the post title" do
    expect(chunker.chunk(post_with(paragraphs(3)))).to all(start_with("#{title}\n\n"))
  end

  it "keeps every chunk, title included, within the maximum length" do
    expect(chunker.chunk(post_with(paragraphs(3)))).to all(satisfy { |chunk| chunk.length <= 200 })
  end

  it "splits on paragraph boundaries" do
    chunks = chunker.chunk(post_with(paragraphs(2, words_each: 30)))

    expect(chunks.size).to eq(2)
    expect(chunks.first).to eq("#{title}\n\n#{Array.new(30, 'p0').join(' ')}")
  end

  it "overlaps consecutive chunks" do
    first, second = chunker.chunk(post_with(paragraphs(2, words_each: 30)))

    expect(second.delete_prefix("#{title}\n\n")).to start_with("p0")
    expect(first).to end_with(second.delete_prefix("#{title}\n\n").split("\n\n").first)
  end

  it "hard-splits a single paragraph that is over the limit" do
    chunks = chunker.chunk(post_with(Array.new(80, "word").join(" ")))

    expect(chunks.size).to be > 1
    expect(chunks).to all(satisfy { |chunk| chunk.length <= 200 })
  end

  it "caps the number of chunks per post so one huge post cannot dominate" do
    chunks = chunker.chunk(post_with(paragraphs(10)))

    expect(chunks.size).to eq(3)
    expect(chunks.first).to include("p0")
    expect(chunks.join).not_to include("p9")
  end

  it "skips posts whose content is below the minimum length" do
    expect(chunker.chunk(post_with("Thanks, +1!"))).to eq([])
  end

  it "skips empty or blank posts" do
    expect(chunker.chunk(post_with(""))).to eq([])
    expect(chunker.chunk(post_with(" \n\n   "))).to eq([])
  end

  it "uses sensible defaults" do
    long_post = post_with(paragraphs(60, words_each: 40))

    chunks = described_class.new.chunk(long_post)

    expect(chunks.size).to eq(described_class::MAX_CHUNKS_PER_POST)
    expect(chunks).to all(satisfy { |chunk| chunk.length <= described_class::MAX_CHUNK_LENGTH })
  end
end
