module SyntheticVectors
  # Points scattered tightly around `groups` well-separated random centers, so clustering has a known answer.
  # Noise is per dimension: ±0.005 over 768 dimensions moves a point about 0.08 away from its unit-length center.
  def separated_groups(groups:, per_group:, seed: 7, noise: 0.005)
    rng = Random.new(seed)
    centers = Array.new(groups) { random_unit_vector(rng) }
    centers.each_with_index.flat_map do |center, group|
      Array.new(per_group) { { group: group, vector: center.map { |value| value + rng.rand(-noise..noise) } } }
    end
  end

  def random_unit_vector(rng, dimensions: Embeddings::DIMENSIONS)
    vector = Array.new(dimensions) { rng.rand(-1.0..1.0) }
    length = Math.sqrt(vector.sum { |value| value * value })
    vector.map { |value| value / length }
  end

  # Two labelings describe the same clusters if they group the same items together, whatever the numbering.
  def same_partition?(labels, other_labels)
    groups_of = ->(list) { list.each_with_index.group_by(&:first).values.map { |pairs| pairs.map(&:last).sort }.sort }
    groups_of.call(labels) == groups_of.call(other_labels)
  end
end

RSpec.configure { |config| config.include SyntheticVectors }
