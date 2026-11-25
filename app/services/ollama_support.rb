# Shared by the Ollama clients: a ruby_llm context aimed at the configured server, and errors that name
# the command that fixes them. Including classes provide #model and #base_url.
module OllamaSupport
  DEFAULT_BASE_URL = "http://localhost:11434/v1".freeze
  MODEL_NOT_FOUND_STATUS = 404

  def self.base_url
    ENV.fetch("OLLAMA_BASE_URL", DEFAULT_BASE_URL)
  end

  private

  def ollama_context
    @ollama_context ||= RubyLLM.context { |config| config.ollama_api_base = base_url }
  end

  def explaining_ollama_errors(error_class)
    yield
  rescue RubyLLM::ConnectionError
    raise error_class, "Ollama is not reachable at #{base_url}. Start it with: ollama serve"
  rescue RubyLLM::Error => error
    raise unless error.response&.status == MODEL_NOT_FOUND_STATUS

    raise error_class, "Ollama has no model named #{model}. Download it with: ollama pull #{model}"
  end
end
