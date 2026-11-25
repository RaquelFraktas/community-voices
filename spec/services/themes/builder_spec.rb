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

  it "reuses the newest clustering for a week, and builds one when there is none" do
    expect { described_class.latest_or_build(week) }.to change(Clustering, :count).by(1)
    expect { described_class.latest_or_build(week) }.not_to change(Clustering, :count)
  end
end
