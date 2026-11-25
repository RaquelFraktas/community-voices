require "rails_helper"

RSpec.describe Themes::Builder do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  before do
    create_themed_chunks(week: week, titles_by_group: [ "Zero-downtime migrations", "ActiveStorage CDN caching", "Kamal deploy hangs" ])
  end

  it "clusters, labels and projects a week's chunks" do
    clustering = described_class.new.build(week)

    expect(clustering.clusters.map(&:label))
      .to contain_exactly("downtime · migrations · zero", "activestorage · caching · cdn", "deploy · hangs · kamal")
    expect(ClusterMembership.where(x: nil).count).to eq(0)
  end

  context "with a labeler other than TF-IDF" do
    let(:named_labeler) do
      Class.new do
        attr_reader :open_transactions

        def label(descriptions, all_titles:)
          @open_transactions = ActiveRecord::Base.connection.open_transactions
          descriptions.keys.each_with_index.to_h { |cluster, index| [ cluster, "Theme #{index + 1}" ] }
        end
      end.new
    end

    it "replaces the TF-IDF labels with the labeler's names, after the clustering transaction" do
      transactions_outside_build = ActiveRecord::Base.connection.open_transactions
      clustering = described_class.new(labeler: named_labeler).build(week)

      expect(clustering.clusters.reload.map(&:label)).to contain_exactly("Theme 1", "Theme 2", "Theme 3")
      expect(named_labeler.open_transactions).to eq(transactions_outside_build)
    end
  end

  context "when labeling fails" do
    let(:failing_labeler) do
      Class.new { def label(*, **) = raise(Llm::UnavailableError, "Ollama is not reachable") }.new
    end

    it "keeps the clustering, its projection and the TF-IDF labels, and logs the failure" do
      allow(Rails.logger).to receive(:warn)

      clustering = nil
      expect { clustering = described_class.new(labeler: failing_labeler).build(week) }
        .to change(Clustering, :count).by(1)

      expect(clustering.clusters.reload.map(&:label))
        .to contain_exactly("downtime · migrations · zero", "activestorage · caching · cdn", "deploy · hangs · kamal")
      expect(clustering.memberships.where(x: nil)).to be_empty
      expect(Rails.logger).to have_received(:warn).with(/Labeling failed, keeping TF-IDF labels: .*not reachable/)
    end
  end

  it "reuses the newest clustering for a week, and builds one when there is none" do
    expect { described_class.latest_or_build(week) }.to change(Clustering, :count).by(1)
    expect { described_class.latest_or_build(week) }.not_to change(Clustering, :count)
  end
end
