# One chunk placed in a RAG report's context. The snapshots keep the report explainable after the chunk is
# replaced or deleted, at which point the database sets chunk_id to null.
class Retrieval < ApplicationRecord
  belongs_to :report
  belongs_to :chunk, optional: true, counter_cache: :retrievals_count

  validates :content_snapshot, :post_title_snapshot, :post_url_snapshot, :query_label, :rank, :distance,
            presence: true
  validates :rank, uniqueness: { scope: :report_id }
end
