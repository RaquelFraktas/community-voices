require "rails_helper"

RSpec.describe Llm::OllamaChatClient do
  subject(:client) { described_class.new(model: "llama3.2", base_url: base_url) }

  let(:base_url) { "http://ollama.test:11434/v1" }
  let(:completions_url) { "#{base_url}/chat/completions" }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  def completion_response(text)
    {
      status: 200, headers: json_headers,
      body: {
        id: "chatcmpl-1", object: "chat.completion", model: "llama3.2",
        choices: [ { index: 0, message: { role: "assistant", content: text }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 20, completion_tokens: 5, total_tokens: 25 }
      }.to_json
    }
  end

  it "sends the system and user prompts to the configured model and returns the reply" do
    stub = stub_request(:post, completions_url)
      .with(body: hash_including(
        model: "llama3.2",
        temperature: described_class::TEMPERATURE,
        messages: [ { role: "system", content: "Be brief." }, { role: "user", content: "Summarize the week." } ]
      ))
      .to_return(completion_response("## Summary\nBusy week."))

    expect(client.complete(system: "Be brief.", user: "Summarize the week.")).to eq("## Summary\nBusy week.")
    expect(stub).to have_been_requested.once
  end

  it "tells you to start Ollama when it is not reachable" do
    stub_request(:post, completions_url).to_raise(Errno::ECONNREFUSED)

    expect { client.complete(system: "s", user: "u") }
      .to raise_error(Llm::UnavailableError, /not reachable at #{Regexp.escape(base_url)}.*ollama serve/)
  end

  it "tells you to pull the model when Ollama does not have it" do
    stub_request(:post, completions_url).to_return(
      status: 404, headers: json_headers,
      body: { error: { message: "model 'llama3.2' not found", type: "not_found_error" } }.to_json
    )

    expect { client.complete(system: "s", user: "u") }
      .to raise_error(Llm::UnavailableError, /ollama pull llama3\.2/)
  end

  describe "configuration" do
    around do |example|
      original = ENV.to_h.slice("OLLAMA_CHAT_MODEL")
      example.run
    ensure
      original.empty? ? ENV.delete("OLLAMA_CHAT_MODEL") : ENV.update(original)
    end

    it "defaults to llama3.2" do
      ENV.delete("OLLAMA_CHAT_MODEL")

      expect(described_class.new.model).to eq("llama3.2")
    end

    it "reads the model from the environment" do
      ENV["OLLAMA_CHAT_MODEL"] = "qwen2.5:7b"

      expect(described_class.new.model).to eq("qwen2.5:7b")
    end
  end
end
