module Embeddings
  # Interface for embedding providers. Implementations return one vector of DIMENSIONS floats per text.
  class Client
    def embed_documents(texts)
      raise NotImplementedError, "#{self.class} must implement #embed_documents"
    end

    def embed_query(text)
      raise NotImplementedError, "#{self.class} must implement #embed_query"
    end
  end
end
