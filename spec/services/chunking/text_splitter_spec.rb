require "rails_helper"

RSpec.describe Chunking::TextSplitter do
  subject(:splitter) { described_class.new(max_length: 100, overlap_length: 20) }

  def paragraph(word, count)
    Array.new(count, word).join(" ")
  end

  it "keeps short text as a single piece" do
    expect(splitter.split("Just one paragraph.")).to eq([ "Just one paragraph." ])
  end

  it "returns nothing for blank text" do
    expect(splitter.split(" \n\n ")).to eq([])
  end

  it "packs consecutive paragraphs into one piece while they fit" do
    expect(splitter.split("First.\n\nSecond.\n\n\nThird.")).to eq([ "First.\n\nSecond.\n\nThird." ])
  end

  it "starts a new piece on a paragraph boundary when the next paragraph does not fit" do
    first = paragraph("alpha", 10)
    second = paragraph("beta", 10)

    pieces = splitter.split("#{first}\n\n#{second}")

    expect(pieces.size).to eq(2)
    expect(pieces.first).to eq(first)
    expect(pieces.last).to end_with(second)
  end

  it "repeats the tail of the previous piece at the start of the next, cut at a word boundary" do
    pieces = splitter.split("#{paragraph('alpha', 15)}\n\n#{paragraph('beta', 10)}")

    overlap = pieces.last.split("\n\n").first
    expect(overlap).to match(/\A(alpha ?)+\z/)
    expect(overlap.length).to be <= 20
    expect(pieces.first).to end_with(overlap)
  end

  it "hard-splits a paragraph longer than the limit, preferring word boundaries" do
    pieces = splitter.split(paragraph("word", 60))

    expect(pieces.size).to be > 1
    expect(pieces).to all(satisfy { |piece| piece.length <= 100 })
    expect(pieces.join(" ").split(/\s+/)).to all(eq("word"))
  end

  it "hard-splits text without any whitespace at the limit" do
    pieces = splitter.split("x" * 250)

    expect(pieces).to all(satisfy { |piece| piece.length <= 100 })
    expect(pieces.first).to eq("x" * 78)
  end

  it "never produces a piece longer than the limit" do
    text = Array.new(30) { |i| paragraph("w#{i}", (i % 7) * 4 + 1) }.join("\n\n")

    expect(splitter.split(text)).to all(satisfy { |piece| piece.length <= 100 })
  end

  it "keeps every word of the text" do
    text = Array.new(12) { |i| paragraph("w#{i}", 9) }.join("\n\n")

    expect(splitter.split(text).join(" ").split(/\s+/).uniq).to eq(text.split(/\s+/).uniq)
  end

  it "can split without overlap" do
    no_overlap = described_class.new(max_length: 100, overlap_length: 0)

    expect(no_overlap.split("#{paragraph('alpha', 15)}\n\n#{paragraph('beta', 10)}").last).to eq(paragraph("beta", 10))
  end

  it "rejects an overlap that would leave too little room for new text" do
    expect { described_class.new(max_length: 100, overlap_length: 50) }.to raise_error(ArgumentError)
  end
end
