require "rails_helper"

RSpec.describe "Status", type: :request do
  let(:models_url) { "#{OllamaSupport.base_url}/models" }

  it "shows every check, the record counts and the latest week" do
    stub_request(:get, models_url).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { data: [ { id: "nomic-embed-text:latest" } ] }.to_json
    )
    create_post(posted_at: Time.zone.parse("2026-11-18 10:00"))

    get status_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Postgres", "pgvector", "Ollama", "Embedding model (nomic-embed-text)",
                                     "Chat model (llama3.2)", "ollama pull llama3.2", "Latest week ingested",
                                     "Nov 16 – Nov 22, 2026", "pipeline:weekly")
  end

  it "still renders when Ollama is down" do
    stub_request(:get, models_url).to_raise(Errno::ECONNREFUSED)

    get status_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("not reachable", "ollama serve")
  end

  it "is linked from the navigation on every page" do
    get root_path

    expect(response.body).to include(%(href="#{status_path}"), %(href="#{retrieval_stats_path}"))
  end
end
