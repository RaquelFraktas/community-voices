require "rails_helper"

RSpec.describe Reports::Retriever do
  around do |example|
    original = ENV["RAG_RETRIEVER"]
    example.run
  ensure
    original ? ENV["RAG_RETRIEVER"] = original : ENV.delete("RAG_RETRIEVER")
  end

  it "uses the theme retriever by default" do
    ENV.delete("RAG_RETRIEVER")

    expect(described_class.configured).to be_a(Reports::ThemeContextRetriever)
  end

  it "uses the facet retriever when RAG_RETRIEVER=facets" do
    ENV["RAG_RETRIEVER"] = "facets"

    expect(described_class.configured).to be_a(Reports::ContextRetriever)
  end

  it "rejects unknown retrievers by name" do
    ENV["RAG_RETRIEVER"] = "clusters"

    expect { described_class.configured }.to raise_error(ArgumentError, /one of themes, facets, got "clusters"/)
  end
end
