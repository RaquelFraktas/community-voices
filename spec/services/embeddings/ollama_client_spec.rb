require "rails_helper"

RSpec.describe Embeddings::OllamaClient do
  subject(:client) { described_class.new(model: "nomic-embed-text", base_url: base_url) }

  let(:base_url) { "http://ollama.test:11434/v1" }
  let(:embeddings_url) { "#{base_url}/embeddings" }

  def vector(seed)
    Array.new(Embeddings::DIMENSIONS) { |i| (seed + i) / 1000.0 }
  end

  def ollama_response(*vectors)
    {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        object: "list", model: "nomic-embed-text",
        data: vectors.each_with_index.map { |values, index| { object: "embedding", index: index, embedding: values } },
        usage: { prompt_tokens: 4, total_tokens: 4 }
      }.to_json
    }
  end

  def stub_embeddings(input:, returning:)
    stub_request(:post, embeddings_url)
      .with(body: hash_including(model: "nomic-embed-text", input: input))
      .to_return(ollama_response(*returning))
  end

  describe "#embed_documents" do
    it "sends every document in one batch, prefixed as a search document" do
      stub = stub_embeddings(input: [ "search_document: first", "search_document: second" ],
                             returning: [ vector(1), vector(2) ])

      vectors = client.embed_documents([ "first", "second" ])

      expect(stub).to have_been_requested.once
      expect(vectors).to eq([ vector(1), vector(2) ])
    end

    it "returns a list of vectors even for a single document" do
      stub_embeddings(input: [ "search_document: only" ], returning: [ vector(1) ])

      expect(client.embed_documents([ "only" ])).to eq([ vector(1) ])
    end

    it "makes no request when there is nothing to embed" do
      expect(client.embed_documents([])).to eq([])
    end
  end

  describe "#embed_query" do
    it "prefixes the text as a search query and returns one vector" do
      stub_embeddings(input: [ "search_query: deployment problems" ], returning: [ vector(7) ])

      expect(client.embed_query("deployment problems")).to eq(vector(7))
    end
  end

  describe "errors" do
    it "tells you to start Ollama when it is not reachable" do
      stub_request(:post, embeddings_url).to_raise(Errno::ECONNREFUSED)

      expect { client.embed_query("anything") }
        .to raise_error(Embeddings::UnavailableError, /not reachable at #{Regexp.escape(base_url)}.*ollama serve/)
    end

    it "tells you to pull the model when Ollama does not have it" do
      stub_request(:post, embeddings_url).to_return(
        status: 404, headers: { "Content-Type" => "application/json" },
        body: { error: { message: "model 'nomic-embed-text' not found", type: "not_found_error" } }.to_json
      )

      expect { client.embed_query("anything") }
        .to raise_error(Embeddings::UnavailableError, /ollama pull nomic-embed-text/)
    end

    it "lets other errors through unchanged" do
      stub_request(:post, embeddings_url).to_return(
        status: 400, headers: { "Content-Type" => "application/json" },
        body: { error: { message: "input too long" } }.to_json
      )

      expect { client.embed_query("anything") }.to raise_error(RubyLLM::BadRequestError)
    end
  end

  describe "configuration" do
    around do |example|
      original = ENV.to_h.slice("OLLAMA_EMBEDDING_MODEL", "OLLAMA_BASE_URL")
      example.run
    ensure
      ENV.update(original)
      (%w[OLLAMA_EMBEDDING_MODEL OLLAMA_BASE_URL] - original.keys).each { |key| ENV.delete(key) }
    end

    it "defaults to nomic-embed-text on the local Ollama" do
      ENV.delete("OLLAMA_EMBEDDING_MODEL")
      ENV.delete("OLLAMA_BASE_URL")

      expect(described_class.new).to have_attributes(model: "nomic-embed-text", base_url: "http://localhost:11434/v1")
    end

    it "reads the model and base URL from the environment" do
      ENV["OLLAMA_EMBEDDING_MODEL"] = "mxbai-embed-large"
      ENV["OLLAMA_BASE_URL"] = "http://gpu-box:11434/v1"

      expect(described_class.new).to have_attributes(model: "mxbai-embed-large", base_url: "http://gpu-box:11434/v1")
    end
  end
end
