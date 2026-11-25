require "rails_helper"

RSpec.describe Themes::LlmLabeler do
  subject(:labeler) { described_class.new(chat_client: chat_client) }

  let(:chat_client) { Llm::FakeChatClient.new(response: "Database migrations in production") }
  let(:migrations) do
    Themes::ClusterDescription.new(
      titles: [ "Rolling back a migration in production", "Migration rollback broke production data" ],
      examples: [ Themes::ClusterExample.new(title: "Rolling back a migration in production",
                                             snippet: "We restore a scrubbed copy and run it there first.") ]
    )
  end
  let(:storage) do
    Themes::ClusterDescription.new(titles: [ "Putting a CDN in front of ActiveStorage" ],
                                   examples: [ Themes::ClusterExample.new(title: "Putting a CDN in front of ActiveStorage",
                                                                          snippet: "Cache misses hit the proxy.") ])
  end
  let(:all_titles) { migrations.titles + storage.titles }

  def tfidf_label(key)
    Themes::Labeler.new.label({ migrations: migrations, storage: storage }, all_titles: all_titles).fetch(key)
  end

  it "names a cluster with the model's reply" do
    expect(labeler.label({ migrations: migrations }, all_titles: all_titles))
      .to eq(migrations: "Database migrations in production")
  end

  it "sends the titles and snippets of the cluster's most central chunks and asks for 2 to 4 words" do
    labeler.label({ migrations: migrations }, all_titles: all_titles)

    prompt = chat_client.prompts.sole
    expect(prompt[:user]).to include("- Rolling back a migration in production: We restore a scrubbed copy",
                                     "2 to 4 words", "no quotes")
    expect(prompt[:system]).to include("Reply with the theme name only")
  end

  it "cleans up and shortens the reply" do
    chatty = Llm::FakeChatClient.new(response: "Theme: \"Testing database migrations before production deploys.\"")

    expect(described_class.new(chat_client: chatty).label({ migrations: migrations }, all_titles: all_titles))
      .to eq(migrations: "Testing database migrations before")
  end

  it "falls back to the title-term label when the reply is junk" do
    junk = Llm::FakeChatClient.new(response: "I'm sorry, but I can't help with that.")

    expect(described_class.new(chat_client: junk).label({ migrations: migrations }, all_titles: all_titles))
      .to eq(migrations: tfidf_label(:migrations))
  end

  it "falls back for a cluster whose name the model already gave to another cluster" do
    labels = labeler.label({ migrations: migrations, storage: storage }, all_titles: all_titles)

    expect(labels).to eq(migrations: "Database migrations in production", storage: tfidf_label(:storage))
  end

  context "when Ollama is unavailable" do
    before do
      allow(chat_client).to receive(:complete).and_raise(Llm::UnavailableError, "Start it with: ollama serve")
    end

    it "falls back to title-term labels for every cluster" do
      expect(labeler.label({ migrations: migrations, storage: storage }, all_titles: all_titles))
        .to eq(migrations: tfidf_label(:migrations), storage: tfidf_label(:storage))
    end

    it "stops asking after the first failure instead of waiting on every cluster" do
      labeler.label({ migrations: migrations, storage: storage }, all_titles: all_titles)

      expect(chat_client).to have_received(:complete).once
    end
  end

  it "falls back when the model returns an error for one cluster, and keeps asking for the next" do
    replies = [ :error, "ActiveStorage CDN caching" ]
    allow(chat_client).to receive(:complete) do
      reply = replies.shift
      reply == :error ? raise(RubyLLM::BadRequestError, "context length exceeded") : reply
    end

    expect(labeler.label({ migrations: migrations, storage: storage }, all_titles: all_titles))
      .to eq(migrations: tfidf_label(:migrations), storage: "ActiveStorage CDN caching")
  end
end

RSpec.describe Themes do
  around do |example|
    original = ENV["THEME_LABELER"]
    example.run
  ensure
    original ? ENV["THEME_LABELER"] = original : ENV.delete("THEME_LABELER")
  end

  it "labels with title terms in tests, so specs never depend on a model" do
    expect(described_class.labeler).to be_a(Themes::Labeler)
  end

  it "uses the LLM labeler outside tests unless THEME_LABELER=tfidf" do
    allow(Rails.env).to receive(:test?).and_return(false)

    expect(described_class.labeler("llm")).to be_a(Themes::LlmLabeler)
    expect(described_class.labeler("tfidf")).to be_a(Themes::Labeler)
  end

  it "rejects unknown labelers by name" do
    expect { described_class.labeler("gpt") }.to raise_error(ArgumentError, /one of llm, tfidf, got "gpt"/)
  end
end
