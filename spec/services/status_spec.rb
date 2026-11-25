require "rails_helper"

RSpec.describe "Status checks" do
  let(:base_url) { "http://ollama.test:11434/v1" }
  let(:models_url) { "#{base_url}/models" }
  let(:models) { { "Embedding model" => "nomic-embed-text", "Chat model" => "llama3.2" } }

  def stub_pulled_models(*ids)
    stub_request(:get, models_url).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { object: "list", data: ids.map { |id| { id: id, object: "model" } } }.to_json
    )
  end

  describe Status::DatabaseCheck do
    it "reports the Postgres version and port" do
      result = described_class.new.call

      expect(result).to be_ok
      expect(result.detail).to match(/\APostgreSQL \d+/)
    end

    it "explains how to start the database when it cannot connect" do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished, "connection refused")

      expect(described_class.new.call).to have_attributes(ok: false, detail: "connection refused", fix: "docker compose up -d")
    end
  end

  describe Status::PgvectorCheck do
    it "passes for pgvector 0.8 or newer" do
      expect(described_class.new.call).to be_ok
    end

    it "fails for an older pgvector, naming the minimum" do
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_return("0.5.0")

      expect(described_class.new.call).to have_attributes(ok: false, detail: "version 0.5.0, need 0.8.0+")
    end
  end

  describe Status::OllamaCheck do
    subject(:results) { described_class.new(base_url: base_url, models: models).call }

    it "reports the server and every configured model as present" do
      stub_pulled_models("llama3.2:latest", "nomic-embed-text:latest")

      expect(results.map(&:name)).to eq([ "Ollama", "Embedding model (nomic-embed-text)", "Chat model (llama3.2)" ])
      expect(results).to all(be_ok)
    end

    it "names the exact pull command for a missing model" do
      stub_pulled_models("nomic-embed-text:latest")

      chat = results.find { |result| result.name.start_with?("Chat model") }
      expect(chat).to have_attributes(ok: false, detail: "not pulled", fix: "ollama pull llama3.2")
    end

    it "asks Ollama only once for every check" do
      stub = stub_pulled_models("llama3.2:latest", "nomic-embed-text:latest")

      results

      expect(stub).to have_been_requested.once
    end

    it "explains how to start Ollama when it is not reachable" do
      stub_request(:get, models_url).to_raise(Errno::ECONNREFUSED)

      expect(results.first).to have_attributes(ok: false, fix: "OLLAMA_CONTEXT_LENGTH=8192 ollama serve")
      expect(results.drop(1).map(&:fix)).to eq([ "ollama pull nomic-embed-text", "ollama pull llama3.2" ])
    end
  end

  describe Status::Overview do
    subject(:overview) { described_class.new(ollama_check: Status::OllamaCheck.new(base_url: base_url, models: models)) }

    before { stub_pulled_models("llama3.2:latest", "nomic-embed-text:latest") }

    it "runs every check" do
      expect(overview.checks.map(&:name)).to eq([ "Postgres", "pgvector", "Ollama", "Embedding model (nomic-embed-text)",
                                                  "Chat model (llama3.2)" ])
      expect(overview).to be_all_ok
    end

    it "counts the records" do
      create_chunk(post: create_post)

      expect(overview.record_counts).to include("Posts" => 1, "Chunks" => 1, "Embedded chunks" => 1, "Reports" => 0)
    end

    it "finds the latest week ingested" do
      create_post(posted_at: Time.zone.parse("2026-11-18 10:00"))

      expect(overview.latest_week_ingested).to eq(Week.new(Date.new(2026, 11, 16)))
    end

    it "gives the next scheduled run of the weekly pipeline" do
      schedule = WeeklyPipeline::Schedule.new(environment: "development")
      with_schedule = described_class.new(ollama_check: Status::OllamaCheck.new(base_url: base_url, models: models),
                                          schedule: schedule)

      travel_to(Time.zone.parse("2026-11-25T10:00:00Z")) do
        expect(with_schedule.next_pipeline_run).to eq(Time.zone.parse("2026-11-30T06:00:00Z"))
      end
    end
  end
end
