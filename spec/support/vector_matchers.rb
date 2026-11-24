RSpec::Matchers.define :match_vector do |expected|
  float32_tolerance = 1e-6

  match do |actual|
    actual.size == expected.size &&
      actual.zip(expected).all? { |stored, original| (stored - original).abs <= float32_tolerance }
  end

  failure_message { |actual| "expected a #{expected.size}-dimension vector matching #{expected.first(3)}..., got #{actual&.first(3)}..." }
end
