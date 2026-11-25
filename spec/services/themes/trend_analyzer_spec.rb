require "rails_helper"

RSpec.describe Themes::TrendAnalyzer do
  subject(:analyzer) { described_class.new }

  let(:weeks) { Array.new(4) { |i| Date.new(2026, 10, 26) + i.weeks } }

  def sample(label, counts)
    member_weeks = counts.each_with_index.flat_map { |count, i| Array.new(count, weeks[i]) }
    described_class::ClusterSample.new(cluster_id: label, label: label, member_weeks: member_weeks)
  end

  def trends_for(*samples)
    analyzer.analyze(samples, weeks: weeks).index_by(&:label)
  end

  it "counts each cluster's members per week, in week order" do
    trend = trends_for(sample("a", [ 1, 2, 0, 3 ]), sample("b", [ 1, 1, 1, 1 ]))["a"]

    expect(trend.weekly_counts).to eq(weeks.zip([ 1, 2, 0, 3 ]).to_h)
    expect(trend.this_week_count).to eq(3)
  end

  it "computes momentum as this week's share over the average earlier share" do
    trends = trends_for(sample("growing", [ 1, 1, 1, 3 ]), sample("other", [ 3, 3, 3, 1 ]))

    expect(trends["growing"].momentum).to eq(3.0)
    expect(trends["other"].momentum).to eq(0.33)
  end

  it "classifies a theme whose share grew by half or more as rising" do
    expect(trends_for(sample("a", [ 1, 1, 1, 3 ]), sample("b", [ 3, 3, 3, 1 ]))["a"].classification).to eq("rising")
  end

  it "classifies a theme with a stable share as steady" do
    expect(trends_for(sample("a", [ 2, 2, 2, 2 ]), sample("b", [ 2, 2, 2, 2 ]))["a"].classification).to eq("steady")
  end

  it "classifies a theme whose share dropped by a third or more as fading" do
    expect(trends_for(sample("a", [ 3, 3, 3, 1 ]), sample("b", [ 1, 1, 1, 3 ]))["a"].classification).to eq("fading")
  end

  it "classifies a theme with no members this week as fading" do
    trend = trends_for(sample("a", [ 2, 1, 1, 0 ]), sample("b", [ 1, 1, 1, 2 ]))["a"]

    expect(trend.classification).to eq("fading")
    expect(trend.momentum).to eq(0.0)
  end

  it "classifies a theme seen for the first time this week as new, with no momentum" do
    trend = trends_for(sample("a", [ 0, 0, 0, 2 ]), sample("b", [ 2, 2, 2, 2 ]))["a"]

    expect(trend.classification).to eq("new")
    expect(trend.momentum).to be_nil
  end

  it "ignores weeks with no chunks at all, such as weeks before ingestion started" do
    trends = trends_for(sample("a", [ 0, 0, 1, 2 ]), sample("b", [ 0, 0, 1, 2 ]))

    expect(trends["a"].momentum).to eq(1.0)
    expect(trends["a"].classification).to eq("steady")
  end

  it "treats every theme as new when the window has only this week's data" do
    trends = trends_for(sample("a", [ 0, 0, 0, 2 ]), sample("b", [ 0, 0, 0, 1 ]))

    expect(trends.values.map(&:classification)).to all(eq("new"))
  end

  it "flags rising and new themes as emerging" do
    trends = trends_for(sample("rising", [ 1, 1, 1, 3 ]), sample("new", [ 0, 0, 0, 2 ]), sample("steady", [ 3, 3, 3, 3 ]))

    expect(trends.values.select(&:emerging?).map(&:label)).to contain_exactly("rising", "new")
  end

  it "returns plain values" do
    expect(trends_for(sample("a", [ 1, 1, 1, 1 ]))["a"]).to be_a(described_class::Trend)
  end
end
