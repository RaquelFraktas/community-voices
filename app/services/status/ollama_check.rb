module Status
  # Asks Ollama for its pulled models once, and answers whether the server and each configured model are there.
  class OllamaCheck
    NAME = "Ollama".freeze
    TIMEOUT_SECONDS = 2

    def initialize(base_url: OllamaSupport.base_url,
                   models: { "Embedding model" => Embeddings::OllamaClient.new.model, "Chat model" => Llm::OllamaChatClient.new.model })
      @base_url = base_url
      @models = models
    end

    def call
      [ server_result, *@models.map { |purpose, model| model_result(purpose, model) } ]
    end

    private

    def server_result
      return Result.passed(NAME, "reachable at #{@base_url}") if pulled_models

      Result.failed(NAME, "not reachable at #{@base_url}", fix: "OLLAMA_CONTEXT_LENGTH=8192 ollama serve")
    end

    def model_result(purpose, model)
      name = "#{purpose} (#{model})"
      return Result.failed(name, "unknown: Ollama is not reachable", fix: "ollama pull #{model}") unless pulled_models
      return Result.passed(name, "pulled") if pulled?(model)

      Result.failed(name, "not pulled", fix: "ollama pull #{model}")
    end

    def pulled?(model)
      pulled_models.any? { |pulled| pulled == model || pulled == "#{model}:latest" }
    end

    def pulled_models
      return @pulled_models if defined?(@pulled_models)

      @pulled_models = fetch_models
    end

    def fetch_models
      response = Faraday.new(url: @base_url, request: { timeout: TIMEOUT_SECONDS, open_timeout: TIMEOUT_SECONDS }) do |faraday|
        faraday.response :raise_error
        faraday.response :json
      end.get("models")
      response.body.fetch("data").map { |model| model["id"] }
    rescue Faraday::Error, KeyError
      nil
    end
  end
end
