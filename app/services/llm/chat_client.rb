module Llm
  # Interface for chat models. Implementations answer one system + user prompt with text and name their model.
  class ChatClient
    def complete(system:, user:)
      raise NotImplementedError, "#{self.class} must implement #complete"
    end

    def model
      raise NotImplementedError, "#{self.class} must implement #model"
    end
  end
end
