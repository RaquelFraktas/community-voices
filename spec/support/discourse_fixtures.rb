module DiscourseFixtures
  def discourse_fixture(name)
    Rails.root.join("spec/fixtures/discourse/#{name}.json").read
  end

  def parsed_discourse_fixture(name)
    JSON.parse(discourse_fixture(name))
  end
end

RSpec.configure { |config| config.include DiscourseFixtures }
