require "rails_helper"

RSpec.describe Themes::Labeler do
  subject(:labeler) { described_class.new }

  def label_titles(titles_by_cluster, all_titles:)
    descriptions = titles_by_cluster.transform_values { |titles| Themes::ClusterDescription.new(titles: titles, examples: []) }
    labeler.label(descriptions, all_titles: all_titles)
  end

  describe "#terms" do
    it "lowercases title words and drops stop words and generic Rails words" do
      expect(labeler.terms("How to use Rails migrations in production with Ruby"))
        .to eq(%w[migrations production])
    end

    it "keeps version numbers and names with digits together" do
      expect(labeler.terms("Upgrading to Rails 8.1.2 with Hotwire and HTTP2"))
        .to eq(%w[upgrading hotwire http2])
    end

    it "drops very short words" do
      expect(labeler.terms("An AI UI on top of my DB")).to eq(%w[top])
    end

    it "lists each term once per title" do
      expect(labeler.terms("Caching, caching, caching")).to eq(%w[caching])
    end
  end

  describe "#label" do
    let(:migration_titles) do
      [
        "How do you check a migration before it runs in production?",
        "Rolling back a migration in production safely",
        "Migration rollback broke production data"
      ]
    end
    let(:storage_titles) do
      [ "Putting a CDN in front of ActiveStorage", "ActiveStorage variants and the CDN cache", "ActiveStorage uploads in production" ]
    end
    let(:all_titles) { migration_titles + storage_titles + [ "Kamal deploys to production" ] }

    it "names each cluster by its most distinctive terms, joined with a middle dot" do
      labels = label_titles({ migrations: migration_titles, storage: storage_titles }, all_titles: all_titles)

      expect(labels[:migrations]).to start_with("migration · ")
      expect(labels[:storage]).to start_with("activestorage · cdn")
    end

    it "prefers words that set a cluster apart over words every cluster shares" do
      labels = label_titles({ migrations: migration_titles, storage: storage_titles }, all_titles: all_titles)

      expect(labels[:migrations].split(" · ").first).not_to eq("production")
      expect(labels[:storage]).not_to include("production")
    end

    it "uses at most three terms" do
      label = label_titles({ migrations: migration_titles }, all_titles: all_titles)[:migrations]

      expect(label.split(" · ").size).to eq(3)
    end

    it "breaks ties alphabetically so labels are stable" do
      label = label_titles({ only: [ "Zeitwerk autoloading" ] }, all_titles: [ "Zeitwerk autoloading" ])[:only]

      expect(label).to eq("autoloading · zeitwerk")
    end

    it "falls back to a generic label when no title has a usable word" do
      expect(label_titles({ empty: [ "How to use Rails?" ] }, all_titles: [ "How to use Rails?" ])[:empty])
        .to eq("miscellaneous")
    end
  end
end
