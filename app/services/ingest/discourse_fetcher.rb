module Ingest
  class DiscourseFetcher < Fetcher
    REGULAR_POST_TYPE = 1
    MAX_POSTS_PER_REQUEST = 20

    def initialize(client: DiscourseClient.new, window: DEFAULT_WINDOW)
      @client = client
      @window = window
      @mapper = DiscoursePostMapper.new(base_url: client.base_url)
    end

    def fetch
      since = @window.ago
      topic_ids_active_since(since)
        .flat_map { |topic_id| posts_in_topic(topic_id) }
        .select { |post| post.posted_at >= since }
    end

    private

    def topic_ids_active_since(since)
      latest_topic_lists
        .slice_after { |topic_list| last_relevant_page?(topic_list, since) }
        .first
        .flat_map { |topic_list| topic_list["topics"] }
        .select { |topic| bumped_since?(topic, since) }
        .map { |topic| topic["id"] }
        .uniq
    end

    def latest_topic_lists
      Enumerator.new do |topic_lists|
        (0..).each { |page| topic_lists << @client.latest(page: page)["topic_list"] }
      end
    end

    def last_relevant_page?(topic_list, since)
      topic_list["more_topics_url"].nil? || topic_list["topics"].any? { |topic| stale_unpinned?(topic, since) }
    end

    def stale_unpinned?(topic, since)
      !topic["pinned"] && !bumped_since?(topic, since)
    end

    def bumped_since?(topic, since)
      Time.zone.parse(topic["bumped_at"]) >= since
    end

    def posts_in_topic(topic_id)
      topic = @client.topic(id: topic_id)
      complete_post_stream(topic)
        .select { |post| regular_and_visible?(post) }
        .map { |post| @mapper.map(topic: topic, post: post) }
    end

    def complete_post_stream(topic)
      post_stream = topic["post_stream"]
      post_stream["posts"] + posts_missing_from(topic["id"], post_stream)
    end

    def posts_missing_from(topic_id, post_stream)
      missing_ids = post_stream["stream"] - post_stream["posts"].pluck("id")
      missing_ids.each_slice(MAX_POSTS_PER_REQUEST).flat_map do |post_ids|
        @client.topic_posts(topic_id: topic_id, post_ids: post_ids).dig("post_stream", "posts")
      end
    end

    def regular_and_visible?(post)
      post["post_type"] == REGULAR_POST_TYPE && !post["hidden"]
    end
  end
end
