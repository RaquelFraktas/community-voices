class Chunk < ApplicationRecord
  belongs_to :post
  has_many :retrievals, dependent: nil
  has_many :cluster_memberships, dependent: nil

  has_neighbors :embedding, dimensions: Embeddings::DIMENSIONS

  validates :position, :content, :content_digest, presence: true
  validates :position, uniqueness: { scope: :post_id }

  scope :pending_embedding, -> { where(embedding: nil) }

  def self.digest(content)
    Digest::SHA256.hexdigest(content)
  end
end
