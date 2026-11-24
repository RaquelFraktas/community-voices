module Ingest
  class DiscourseClient
    DEFAULT_BASE_URL = "https://discuss.rubyonrails.org".freeze
    USER_AGENT = "CommunityVoices/0.1 (weekly community digest; take-home coding challenge)".freeze
    DEFAULT_PAUSE_SECONDS = 0.5

    attr_reader :base_url

    def initialize(base_url: DEFAULT_BASE_URL, pause_seconds: DEFAULT_PAUSE_SECONDS)
      @base_url = base_url
      @pause_seconds = pause_seconds
      @requests_made = 0
    end

    def latest(page:)
      get("/latest.json", page: page)
    end

    def topic(id:)
      get("/t/#{id}.json")
    end

    def topic_posts(topic_id:, post_ids:)
      get("/t/#{topic_id}/posts.json", post_ids: post_ids)
    end

    private

    def get(path, params = {})
      pause_between_requests
      connection.get(path, params).body
    end

    def pause_between_requests
      sleep(@pause_seconds) if @requests_made.positive?
      @requests_made += 1
    end

    def connection
      @connection ||= Faraday.new(url: base_url, headers: { "User-Agent" => USER_AGENT }) do |faraday|
        faraday.response :raise_error
        faraday.response :json
      end
    end
  end
end
