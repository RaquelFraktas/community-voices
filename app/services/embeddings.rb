module Embeddings
  DIMENSIONS = 768

  def self.client
    Rails.env.test? ? FakeClient.new : OllamaClient.new
  end
end
