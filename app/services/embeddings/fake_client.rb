module Embeddings
  # Deterministic stand-in for tests: the same text always maps to the same unit vector.
  class FakeClient < Client
    def embed_documents(texts)
      texts.map { |text| vector_for(text) }
    end

    def embed_query(text)
      vector_for(text)
    end

    private

    def vector_for(text)
      random = Random.new(Digest::SHA256.hexdigest(text).to_i(16))
      normalize(Array.new(DIMENSIONS) { random.rand(-1.0..1.0) })
    end

    def normalize(vector)
      length = Math.sqrt(vector.sum { |value| value * value })
      vector.map { |value| value / length }
    end
  end
end
