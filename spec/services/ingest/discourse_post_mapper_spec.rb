require "rails_helper"

RSpec.describe Ingest::DiscoursePostMapper do
  subject(:fetched_post) { described_class.new(base_url: "https://discuss.rubyonrails.org").map(topic: topic, post: post) }

  let(:topic) { parsed_discourse_fixture("topic_91984") }
  let(:post) { topic.dig("post_stream", "posts").second }

  it "maps a Discourse post to a FetchedPost" do
    expect(fetched_post).to have_attributes(
      source: "discourse",
      source_id: "268507",
      title: "How do you check a migration before it runs in production?",
      author: "Lorin_Thwaits",
      url: "https://discuss.rubyonrails.org/t/how-do-you-check-a-migration-before-it-runs-in-production/91984/2",
      posted_at: Time.zone.parse("2026-11-14T18:50:48.724Z"),
      reply_count: 1
    )
  end

  it "stores the body as plain text" do
    expect(fetched_post.body).to be_present
    expect(fetched_post.body).not_to match(/<\/?[a-z]+/)
  end
end
