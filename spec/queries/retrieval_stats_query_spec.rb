require "rails_helper"

RSpec.describe RetrievalStatsQuery do
  subject(:stats) { described_class.new(limit: 2) }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:clustering) do
    Clustering.create!(window_start: week.starts_on - 5.weeks, window_end: week.ends_on, k: 3, random_seed: 42)
  end
  let(:theme_report) { Report.create!(week_of: week.starts_on, variant: :rag, clustering: clustering) }
  let(:facet_report) { Report.create!(week_of: week.starts_on, variant: :rag) }

  let(:upgrade_post) { create_post(title: "Upgrading to Rails 8.1") }
  let(:kamal_post) { create_post(title: "Kamal deploys hang") }
  let(:upgrade_intro) { create_chunk(post: upgrade_post, position: 0, content: "Upgrading to Rails 8.1\n\nWe upgraded today.") }
  let(:upgrade_details) { create_chunk(post: upgrade_post, position: 1, content: "Upgrading to Rails 8.1\n\nDetails.") }
  let(:kamal_chunk) { create_chunk(post: kamal_post, content: "Kamal deploys hang\n\nIt hangs on boot.") }

  def retrieve(chunk, report:, rank:, label:, at: Time.current)
    report.retrievals.create!(retrieval_attributes_for(chunk, rank: rank, query_label: label).merge(created_at: at))
  end

  before do
    retrieve(upgrade_intro, report: theme_report, rank: 1, label: "upgrades · rails", at: 2.days.ago)
    retrieve(kamal_chunk, report: theme_report, rank: 2, label: "kamal · deploys", at: 2.days.ago)
    retrieve(upgrade_details, report: theme_report, rank: 3, label: "upgrades · rails", at: 2.days.ago)
    retrieve(upgrade_intro, report: facet_report, rank: 1, label: "new releases and upgrades", at: 1.hour.ago)
    retrieve(kamal_chunk, report: facet_report, rank: 2, label: "deployment and infrastructure", at: 3.hours.ago)
    retrieve(upgrade_details, report: Report.create!(week_of: week.starts_on, variant: :rag, clustering: clustering),
             rank: 1, label: "upgrades · rails")
  end

  describe "#top_chunks" do
    it "lists the most-retrieved chunks first, then the most recently retrieved, up to the limit" do
      rows = stats.top_chunks

      expect(rows.map(&:retrievals_count)).to eq([ 2, 2 ])
      expect(rows.map(&:snippet)).to eq([ "Details.", "We upgraded today." ])
    end

    it "gives each chunk its post title and url, a snippet without the title, and when it was last retrieved" do
      row = stats.top_chunks.first

      expect(row).to have_attributes(post_title: "Upgrading to Rails 8.1", post_url: upgrade_post.url, snippet: "Details.")
      expect(row.last_retrieved_at).to be_within(1.second).of(Time.current)
    end

    it "leaves out chunks that were never retrieved" do
      create_chunk(post: create_post(title: "Never retrieved"))

      expect(described_class.new.top_chunks.map(&:post_title)).not_to include("Never retrieved")
    end
  end

  describe "#top_posts" do
    it "sums the retrievals of each post's chunks" do
      expect(stats.top_posts.map { |row| [ row.title, row.retrievals_count ] })
        .to eq([ [ "Upgrading to Rails 8.1", 4 ], [ "Kamal deploys hang", 2 ] ])
    end
  end

  describe "#top_themes" do
    it "counts retrievals per cluster label, from theme-based reports only" do
      expect(stats.top_themes.map { |row| [ row.label, row.retrievals_count ] })
        .to eq([ [ "upgrades · rails", 3 ], [ "kamal · deploys", 1 ] ])
    end

    it "keeps counting a theme's retrievals after their chunks are replaced" do
      Chunk.where(id: upgrade_details.id).delete_all

      expect(described_class.new.top_themes.first).to have_attributes(label: "upgrades · rails", retrievals_count: 3)
    end
  end
end
