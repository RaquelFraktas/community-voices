module Llm
  def self.client
    Rails.env.test? ? FakeChatClient.new : OllamaChatClient.new
  end
end
