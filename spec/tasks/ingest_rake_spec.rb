require "rails_helper"
require "rake"

RSpec.describe "rake ingest:discourse" do
  let(:base_url) { Ingest::DiscourseClient::DEFAULT_BASE_URL }
  let(:json_headers) { { "Content-Type" => "application/json" } }
  let(:latest_with_one_topic) do
    parsed_discourse_fixture("latest").tap do |latest|
      latest["topic_list"]["topics"].select! { |topic| topic["id"] == 91984 }
      latest["topic_list"]["more_topics_url"] = nil
    end
  end

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  around { |example| travel_to(Time.zone.parse("2026-11-24T18:00:00Z")) { example.run } }

  before do
    Rake::Task["ingest:discourse"].reenable
    allow_any_instance_of(Ingest::DiscourseClient).to receive(:sleep)
    stub_request(:get, "#{base_url}/latest.json?page=0")
      .to_return(body: latest_with_one_topic.to_json, headers: json_headers)
    stub_request(:get, "#{base_url}/t/91984.json")
      .to_return(body: discourse_fixture("topic_91984"), headers: json_headers)
  end

  it "stores the posts from the requested window and prints a summary" do
    expect { Rake::Task["ingest:discourse"].invoke("7") }
      .to output("Fetched 2 posts (2 new). 2 posts stored in total.\n").to_stdout

    expect(Post.pluck(:source_id)).to contain_exactly("268523", "268542")
  end

  it "is idempotent across reruns" do
    2.times do
      Rake::Task["ingest:discourse"].reenable
      expect { Rake::Task["ingest:discourse"].invoke("7") }.to output.to_stdout
    end

    expect(Post.count).to eq(2)
  end
end
