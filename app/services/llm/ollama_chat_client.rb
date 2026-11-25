module Llm
  class OllamaChatClient < ChatClient
    include OllamaSupport

    DEFAULT_MODEL = "llama3.2".freeze
    TEMPERATURE = 0.3

    attr_reader :model, :base_url

    def initialize(model: ENV.fetch("OLLAMA_CHAT_MODEL", DEFAULT_MODEL), base_url: OllamaSupport.base_url)
      @model = model
      @base_url = base_url
    end

    def complete(system:, user:)
      explaining_ollama_errors(UnavailableError) do
        new_chat.with_instructions(system).ask(user).content
      end
    end

    private

    def new_chat
      ollama_context.chat(model: model, provider: :ollama, assume_model_exists: true).with_temperature(TEMPERATURE)
    end
  end
end
