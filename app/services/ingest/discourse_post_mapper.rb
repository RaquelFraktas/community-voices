module Ingest
  class DiscoursePostMapper
    SOURCE = "discourse".freeze

    def initialize(base_url:)
      @base_url = base_url
    end

    def map(topic:, post:)
      FetchedPost.new(
        source: SOURCE,
        source_id: post["id"].to_s,
        title: topic["title"],
        body: HtmlToText.call(post["cooked"]),
        author: post["username"],
        url: URI.join(@base_url, post["post_url"]).to_s,
        posted_at: Time.zone.parse(post["created_at"]),
        reply_count: post["reply_count"].to_i
      )
    end
  end
end
