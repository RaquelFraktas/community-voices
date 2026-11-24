require "rails_helper"

RSpec.describe Ingest::Pipeline do
  let(:fetched_posts) do
    %w[1 2].map do |source_id|
      Ingest::FetchedPost.new(
        source: "test", source_id: source_id, title: "Title", body: "Body",
        author: "matz", url: "https://example.com/#{source_id}", posted_at: 1.hour.ago, reply_count: 0
      )
    end
  end
  let(:fetcher) { instance_double(Ingest::Fetcher, fetch: fetched_posts) }

  it "imports whatever the fetcher returns" do
    described_class.new(fetcher: fetcher).run

    expect(Post.pluck(:source_id)).to contain_exactly("1", "2")
  end

  it "summarizes fetched, new and total posts" do
    Post.create!(fetched_posts.first.to_h)

    summary = described_class.new(fetcher: fetcher).run

    expect(summary).to have_attributes(fetched_count: 2, new_count: 1, total_count: 2)
    expect(summary.to_s).to eq("Fetched 2 posts (1 new). 2 posts stored in total.")
  end
end
