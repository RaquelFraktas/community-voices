class ClusterMembership < ApplicationRecord
  belongs_to :cluster
  belongs_to :chunk

  validates :distance_to_centroid, presence: true
end
