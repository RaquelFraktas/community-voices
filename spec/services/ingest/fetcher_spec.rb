require "rails_helper"

RSpec.describe Ingest::Fetcher do
  it "requires implementations to define #fetch" do
    expect { described_class.new.fetch }.to raise_error(NotImplementedError)
  end
end
