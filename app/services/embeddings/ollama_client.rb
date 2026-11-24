module Embeddings
  # Embeds text with a local Ollama model through ruby_llm. nomic-embed-text expects a task prefix
  # telling it whether a text is a document to be found or a query looking for documents.
  class OllamaClient < Client
    DEFAULT_MODEL = "nomic-embed-text".freeze
    DEFAULT_BASE_URL = "http://localhost:11434/v1".freeze
    DOCUMENT_PREFIX = "search_document: ".freeze
    QUERY_PREFIX = "search_query: ".freeze
    MODEL_NOT_FOUND_STATUS = 404

    attr_reader :model, :base_url

    def initialize(model: ENV.fetch("OLLAMA_EMBEDDING_MODEL", DEFAULT_MODEL),
                   base_url: ENV.fetch("OLLAMA_BASE_URL", DEFAULT_BASE_URL))
      @model = model
      @base_url = base_url
    end

    def embed_documents(texts)
      return [] if texts.empty?

      embed(texts.map { |text| DOCUMENT_PREFIX + text })
    end

    def embed_query(text)
      embed([ QUERY_PREFIX + text ]).first
    end

    private

    def embed(inputs)
      context.embed(inputs, model: model, provider: :ollama, assume_model_exists: true).vectors
    rescue RubyLLM::ConnectionError
      raise UnavailableError, "Ollama is not reachable at #{base_url}. Start it with: ollama serve"
    rescue RubyLLM::Error => error
      raise unless model_missing?(error)

      raise UnavailableError, "Ollama has no model named #{model}. Download it with: ollama pull #{model}"
    end

    def model_missing?(error)
      error.response&.status == MODEL_NOT_FOUND_STATUS
    end

    def context
      @context ||= RubyLLM.context { |config| config.ollama_api_base = base_url }
    end
  end
end
