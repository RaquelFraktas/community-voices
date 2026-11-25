module Embeddings
  # Embeds text with a local Ollama model through ruby_llm. nomic-embed-text expects a task prefix
  # telling it whether a text is a document to be found or a query looking for documents.
  class OllamaClient < Client
    include OllamaSupport

    DEFAULT_MODEL = "nomic-embed-text".freeze
    DOCUMENT_PREFIX = "search_document: ".freeze
    QUERY_PREFIX = "search_query: ".freeze

    attr_reader :model, :base_url

    def initialize(model: ENV.fetch("OLLAMA_EMBEDDING_MODEL", DEFAULT_MODEL), base_url: OllamaSupport.base_url)
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
      explaining_ollama_errors(UnavailableError) do
        ollama_context.embed(inputs, model: model, provider: :ollama, assume_model_exists: true).vectors
      end
    end
  end
end
