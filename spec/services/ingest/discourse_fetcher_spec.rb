require "rails_helper"

RSpec.describe Ingest::DiscourseFetcher do
  subject(:fetcher) { described_class.new(client: client, window: window) }

  let(:now) { Time.zone.parse("2026-11-24T18:00:00Z") }
  let(:window) { 7.days }
  let(:client) { instance_double(Ingest::DiscourseClient, base_url: "https://discuss.rubyonrails.org") }
  let(:empty_topic) { { "title" => "Empty", "post_stream" => { "posts" => [], "stream" => [] } } }

  around { |example| travel_to(now) { example.run } }

  def topic_summary(id, bumped_at:, pinned: false)
    { "id" => id, "bumped_at" => bumped_at.iso8601, "pinned" => pinned }
  end

  def latest_page(*topics, more: true)
    { "topic_list" => { "topics" => topics, "more_topics_url" => (more ? "/latest?page=next" : nil) } }
  end

  describe "choosing topics" do
    before { allow(client).to receive(:topic).and_return(empty_topic) }

    it "fetches topics bumped within the window from the real latest page, ignoring the old pinned topic" do
      allow(client).to receive(:latest).with(page: 0).and_return(parsed_discourse_fixture("latest"))

      fetcher.fetch

      [ 91793, 91984, 91861, 91996, 91991, 91694, 91990 ].each do |id|
        expect(client).to have_received(:topic).with(id: id)
      end
      expect(client).to have_received(:topic).exactly(7).times
      expect(client).not_to have_received(:latest).with(page: 1)
    end

    it "keeps paging while every topic on a page is recent" do
      allow(client).to receive(:latest).with(page: 0).and_return(latest_page(topic_summary(1, bumped_at: 1.day.ago)))
      allow(client).to receive(:latest).with(page: 1)
        .and_return(latest_page(topic_summary(2, bumped_at: 2.days.ago), topic_summary(3, bumped_at: 8.days.ago)))

      fetcher.fetch

      expect(client).to have_received(:topic).with(id: 1)
      expect(client).to have_received(:topic).with(id: 2)
      expect(client).not_to have_received(:topic).with(id: 3)
      expect(client).not_to have_received(:latest).with(page: 2)
    end

    it "stops when Discourse reports no more pages" do
      allow(client).to receive(:latest).with(page: 0)
        .and_return(latest_page(topic_summary(1, bumped_at: 1.day.ago), more: false))

      fetcher.fetch

      expect(client).to have_received(:latest).once
    end
  end

  describe "collecting posts" do
    before do
      allow(client).to receive(:latest).with(page: 0)
        .and_return(latest_page(topic_summary(topic_id, bumped_at: 1.day.ago), more: false))
      allow(client).to receive(:topic).with(id: topic_id).and_return(parsed_discourse_fixture("topic_#{topic_id}"))
    end

    context "with a topic whose posts all arrive in the first payload" do
      let(:topic_id) { 91984 }

      it "returns visible posts published within the window as FetchedPost values" do
        posts = fetcher.fetch

        expect(posts).to all(be_a(Ingest::FetchedPost))
        expect(posts.map(&:source_id)).to eq(%w[268523 268542])
      end

      it "skips posts hidden by community flags" do
        expect(fetcher.fetch.map(&:source_id)).not_to include("268529")
      end
    end

    context "with a topic longer than the first payload" do
      let(:topic_id) { 68402 }
      let(:window) { 20.years }

      before do
        allow(client).to receive(:topic_posts)
          .with(topic_id: 68402, post_ids: [ 267604 ])
          .and_return(parsed_discourse_fixture("topic_68402_posts"))
      end

      it "fetches the posts missing from the first payload" do
        posts = fetcher.fetch

        expect(posts.size).to eq(21)
        expect(posts.last.source_id).to eq("267604")
      end
    end
  end
end
