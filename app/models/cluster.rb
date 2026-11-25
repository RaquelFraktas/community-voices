class Cluster < ApplicationRecord
  belongs_to :clustering
  has_many :memberships, -> { order(:distance_to_centroid) }, class_name: "ClusterMembership",
                                                            dependent: :delete_all, inverse_of: :cluster
  has_many :chunks, through: :memberships

  has_neighbors :centroid, dimensions: Embeddings::DIMENSIONS

  validates :position, :centroid, :size, presence: true
end
