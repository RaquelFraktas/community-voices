module Ingest
  class Pipeline
    Summary = Data.define(:fetched_count, :new_count, :total_count) do
      def to_s
        "Fetched #{fetched_count} posts (#{new_count} new). #{total_count} posts stored in total."
      end
    end

    def initialize(fetcher:, importer: PostImporter.new)
      @fetcher = fetcher
      @importer = importer
    end

    def run
      fetched_posts = @fetcher.fetch
      count_before = Post.count
      @importer.import(fetched_posts)
      Summary.new(fetched_count: fetched_posts.size, new_count: Post.count - count_before, total_count: Post.count)
    end
  end
end
