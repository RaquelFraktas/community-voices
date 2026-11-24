require "rails_helper"

RSpec.describe Ingest::PostImporter do
  subject(:importer) { described_class.new }

  def fetched_post(source_id: "1", title: "Original title")
    Ingest::FetchedPost.new(
      source: "discourse", source_id: source_id, title: title, body: "Body",
      author: "dhh", url: "https://example.com/t/#{source_id}", posted_at: 1.day.ago, reply_count: 0
    )
  end

  it "stores fetched posts" do
    importer.import([ fetched_post(source_id: "1"), fetched_post(source_id: "2") ])

    expect(Post.pluck(:source_id)).to contain_exactly("1", "2")
  end

  it "returns how many posts were written" do
    expect(importer.import([ fetched_post(source_id: "1"), fetched_post(source_id: "2") ])).to eq(2)
  end

  it "updates existing posts instead of duplicating them on rerun" do
    importer.import([ fetched_post(title: "Original title") ])
    importer.import([ fetched_post(title: "Edited title") ])

    expect(Post.count).to eq(1)
    expect(Post.sole.title).to eq("Edited title")
  end

  it "tolerates the same post appearing twice in one batch" do
    expect { importer.import([ fetched_post, fetched_post ]) }.to change(Post, :count).by(1)
  end

  it "does nothing when there is nothing to import" do
    expect(importer.import([])).to eq(0)
  end
end
