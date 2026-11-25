module Llm
  # Stand-in for tests: answers every prompt with the same canned text and remembers the prompts it got.
  class FakeChatClient < ChatClient
    CANNED_RESPONSE = <<~MARKDOWN.freeze
      ## Summary
      A quiet week on the forum [1].

      ## Top discussions this past week
      - Upgrading to Rails 8 [1]

      ## Recurring themes
      - Upgrades

      ## Predictions for next week
      - More upgrade questions, because a release just shipped.
    MARKDOWN

    attr_reader :model, :prompts

    def initialize(response: CANNED_RESPONSE, model: "fake-chat")
      @response = response
      @model = model
      @prompts = []
    end

    def complete(system:, user:)
      @prompts << { system: system, user: user }
      @response
    end
  end
end
