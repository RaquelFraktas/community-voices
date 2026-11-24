module Ingest
  class PostImporter
    UNIQUE_KEY = %i[source source_id].freeze
    BATCH_SIZE = 500

    def import(fetched_posts)
      unique_rows(fetched_posts).each_slice(BATCH_SIZE).sum do |rows|
        Post.upsert_all(rows, unique_by: UNIQUE_KEY).length
      end
    end

    private

    def unique_rows(fetched_posts)
      fetched_posts.map(&:to_h).uniq { |row| row.values_at(*UNIQUE_KEY) }
    end
  end
end
