class Post < ApplicationRecord
  has_many :chunks, -> { order(:position) }, dependent: :delete_all, inverse_of: :post

  validates :source, :source_id, :title, :url, :posted_at, presence: true
  validates :source_id, uniqueness: { scope: :source }

  scope :posted_since, ->(time) { where(posted_at: time..) }
  scope :posted_between, ->(since, before) { where(posted_at: since...before) }
end
