require "rails_helper"

RSpec.describe Themes::UnitVectors do
  it "scales a vector to length 1, keeping its direction" do
    expect(described_class.unit_length([ 3.0, 4.0 ])).to eq([ 0.6, 0.8 ])
  end

  it "leaves a zero vector alone" do
    expect(described_class.unit_length([ 0.0, 0.0 ])).to eq([ 0.0, 0.0 ])
  end

  it "makes clustering depend on direction, not length, as cosine search does" do
    rng = Random.new(5)
    directions = Array.new(3) { random_unit_vector(rng) }
    points = directions.each_with_index.flat_map do |direction, group|
      [ 1.0, 9.0, 3.0, 6.0 ].map { |scale| { group: group, vector: direction.map { |value| value * scale } } }
    end

    labels = Themes::KMeansSelector.new.select(points.map { |point| described_class.unit_length(point[:vector]) }).labels

    expect(same_partition?(labels, points.map { |point| point[:group] })).to be(true)
  end
end
