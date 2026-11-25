require "rails_helper"

RSpec.describe Llm::FakeChatClient do
  it "answers with canned markdown" do
    expect(described_class.new.complete(system: "s", user: "u")).to include("## Summary")
  end

  it "can be given a specific response" do
    expect(described_class.new(response: "Hi").complete(system: "s", user: "u")).to eq("Hi")
  end

  it "remembers the prompts it was sent" do
    client = described_class.new
    client.complete(system: "rules", user: "question")

    expect(client.prompts).to eq([ { system: "rules", user: "question" } ])
  end
end

RSpec.describe Llm do
  it "uses the fake chat client in tests" do
    expect(described_class.client).to be_a(Llm::FakeChatClient)
  end
end
