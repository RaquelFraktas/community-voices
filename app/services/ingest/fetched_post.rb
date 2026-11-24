module Ingest
  FetchedPost = Data.define(:source, :source_id, :title, :body, :author, :url, :posted_at, :reply_count)
end
