require "rails_helper"

RSpec.describe Ingest::DiscourseClient do
  subject(:client) { described_class.new(pause_seconds: 0) }

  let(:base_url) { described_class::DEFAULT_BASE_URL }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "#latest" do
    it "requests the given page of latest topics and parses the JSON" do
      stub_request(:get, "#{base_url}/latest.json?page=2")
        .to_return(body: discourse_fixture("latest"), headers: json_headers)

      topics = client.latest(page: 2).dig("topic_list", "topics")

      expect(topics.first["title"]).to eq("Welcome to the Ruby on Rails forum")
    end

    it "identifies itself with a descriptive User-Agent" do
      stub = stub_request(:get, "#{base_url}/latest.json?page=0")
        .with(headers: { "User-Agent" => described_class::USER_AGENT })
        .to_return(body: "{}", headers: json_headers)

      client.latest(page: 0)

      expect(stub).to have_been_requested
    end
  end

  describe "#topic" do
    it "requests the topic by id" do
      stub_request(:get, "#{base_url}/t/91984.json")
        .to_return(body: discourse_fixture("topic_91984"), headers: json_headers)

      expect(client.topic(id: 91984)["id"]).to eq(91984)
    end
  end

  describe "#topic_posts" do
    it "requests specific posts of a topic by id" do
      stub_request(:get, "#{base_url}/t/68402/posts.json")
        .with(query: "post_ids[]=267604&post_ids[]=267605")
        .to_return(body: discourse_fixture("topic_68402_posts"), headers: json_headers)

      posts = client.topic_posts(topic_id: 68402, post_ids: [ 267604, 267605 ])

      expect(posts.dig("post_stream", "posts").map { |post| post["id"] }).to eq([ 267604 ])
    end
  end

  it "raises on HTTP errors" do
    stub_request(:get, "#{base_url}/t/1.json").to_return(status: 404)

    expect { client.topic(id: 1) }.to raise_error(Faraday::ResourceNotFound)
  end

  it "pauses between consecutive requests" do
    patient_client = described_class.new(pause_seconds: 0.25)
    allow(patient_client).to receive(:sleep)
    stub_request(:get, /latest\.json/).to_return(body: "{}", headers: json_headers)

    2.times { |page| patient_client.latest(page: page) }

    expect(patient_client).to have_received(:sleep).with(0.25).once
  end
end
