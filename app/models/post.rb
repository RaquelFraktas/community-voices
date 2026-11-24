class Post < ApplicationRecord
  validates :source, :source_id, :title, :url, :posted_at, presence: true
  validates :source_id, uniqueness: { scope: :source }

  scope :posted_since, ->(time) { where(posted_at: time..) }
end
