require "rails_helper"

RSpec.describe Reports::ComparisonMetrics do
  subject(:metrics) do
    described_class.new(rag: rag, baseline: baseline, retrievals: retrievals, post_titles: post_titles)
  end

  let(:report_double) { Struct.new(:body, :generation_seconds) }
  let(:retrieval_double) { Struct.new(:rank, :post_url_snapshot, :post_title_snapshot) }
  let(:rag) { report_double.new(rag_body, 41.26) }
  let(:baseline) { report_double.new(baseline_body, 12.04) }
  let(:rag_body) { "" }
  let(:baseline_body) { "" }
  let(:retrievals) do
    [
      retrieval_double.new(1, "https://forum.test/t/upgrade/1", "Upgrading to Rails 8.1"),
      retrieval_double.new(2, "https://forum.test/t/upgrade/2", "Upgrading to Rails 8.1"),
      retrieval_double.new(3, "https://forum.test/t/kamal/1", "Kamal deploy hangs on health check")
    ]
  end
  let(:post_titles) do
    [ "Upgrading to Rails 8.1", "Kamal deploy hangs on health check", "Solid Queue recurring tasks", "Upgrading to Rails 8.1" ]
  end

  describe "citations" do
    let(:rag_body) { "Upgrades dominated [1]. Some deploys hung [3][2]. Others agreed [1, 2]. A claim with no source [7]." }

    it "finds every [n], including lists and adjacent citations" do
      expect(metrics.citations(:rag)).to eq([ 1, 3, 2, 1, 2, 7 ])
    end

    it "counts citations that match a context entry as valid" do
      expect(metrics.valid_citations(:rag)).to eq([ 1, 3, 2, 1, 2 ])
    end

    it "counts citations without a matching context entry as invalid" do
      expect(metrics.invalid_citations(:rag)).to eq([ 7 ])
    end

    it "treats zero and numbers past the last entry as invalid" do
      rag.body = "Nothing at [0] or [4]."

      expect(metrics.invalid_citations(:rag)).to eq([ 0, 4 ])
    end

    it "ignores markdown links and other bracketed text" do
      rag.body = "See [the guide](https://guides.rubyonrails.org) and [Rails 8] notes."

      expect(metrics.citations(:rag)).to eq([])
    end

    it "counts the distinct posts behind the valid citations" do
      expect(metrics.distinct_posts_cited(:rag))
        .to contain_exactly("https://forum.test/t/upgrade/1", "https://forum.test/t/upgrade/2", "https://forum.test/t/kamal/1")
    end

    context "in the baseline, which was given no context" do
      let(:baseline_body) { "People discussed upgrades [1] and deploys [2]." }

      it "counts every citation as invalid" do
        expect(metrics.valid_citations(:baseline)).to eq([])
        expect(metrics.invalid_citations(:baseline)).to eq([ 1, 2 ])
        expect(metrics.distinct_posts_cited(:baseline)).to eq([])
      end
    end

    it "handles a report with no citations" do
      expect(metrics.citations(:baseline)).to eq([])
    end
  end

  describe "#titles_mentioned" do
    it "finds titles quoted exactly, ignoring case and punctuation" do
      rag.body = "The thread \"upgrading to rails 8.1!\" got the most replies."

      expect(metrics.titles_mentioned(:rag)).to eq([ "Upgrading to Rails 8.1" ])
    end

    it "finds titles paraphrased within one line" do
      baseline.body = "- Kamal deploys hang during the health check, several people reported."

      expect(metrics.titles_mentioned(:baseline)).to eq([ "Kamal deploy hangs on health check" ])
    end

    it "does not match a title whose words are scattered across the report" do
      baseline.body = "Kamal came up.\n\nSo did a health check.\n\nOne deploy hangs."

      expect(metrics.titles_mentioned(:baseline)).to eq([])
    end

    it "needs an exact match for short titles" do
      metrics_with_short_title = described_class.new(rag: rag, baseline: baseline, retrievals: [], post_titles: [ "Solid Queue" ])
      rag.body = "Queue sizes were solid this week."

      expect(metrics_with_short_title.titles_mentioned(:rag)).to eq([])
    end

    it "counts each title once even when several posts share it" do
      rag.body = "Upgrading to Rails 8.1 was everywhere. Upgrading to Rails 8.1, again."

      expect(metrics.titles_mentioned(:rag)).to eq([ "Upgrading to Rails 8.1" ])
    end
  end

  describe "#word_count" do
    it "counts words, not markdown symbols or citations" do
      rag.body = "## Summary\n- It's a **busy** week [1][2]."

      expect(metrics.word_count(:rag)).to eq(5)
    end

    it "counts a version number as one word" do
      rag.body = "Rails 8.1.2 shipped."

      expect(metrics.word_count(:rag)).to eq(3)
    end

    it "is zero for a missing body" do
      expect(described_class.new(rag: report_double.new(nil, nil), baseline: baseline, retrievals: [], post_titles: [])
        .word_count(:rag)).to eq(0)
    end
  end

  describe "#generation_seconds" do
    it "rounds to a tenth of a second" do
      expect([ metrics.generation_seconds(:rag), metrics.generation_seconds(:baseline) ]).to eq([ 41.3, 12.0 ])
    end
  end

  describe "#rows" do
    let(:rag_body) { "## Summary\nUpgrading to Rails 8.1 dominated [1][3][9]." }
    let(:baseline_body) { "## Summary\nPeople upgraded [1]." }

    it "lays out every metric for both variants" do
      expect(metrics.rows.map { |row| [ row.label, row.rag, row.baseline ] }).to eq([
        [ "Context entries", 3, 0 ],
        [ "Valid citations", 2, 0 ],
        [ "Invalid citations", 1, 1 ],
        [ "Distinct posts cited", 2, 0 ],
        [ "Post titles mentioned (of 3)", 1, 0 ],
        [ "Words", 6, 3 ],
        [ "Generation time (s)", 41.3, 12.0 ]
      ])
    end
  end
end
