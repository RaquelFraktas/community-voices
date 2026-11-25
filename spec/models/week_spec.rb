require "rails_helper"

RSpec.describe Week do
  let(:week) { described_class.new(Date.new(2026, 11, 16)) }

  it "always starts on a Monday" do
    expect(described_class.new(Date.new(2026, 11, 19)).starts_on).to eq(Date.new(2026, 11, 16))
    expect(described_class.containing(Time.zone.parse("2026-11-22 23:59")).starts_on).to eq(Date.new(2026, 11, 16))
  end

  it "parses an ISO date" do
    expect(described_class.parse("2026-11-18")).to eq(week)
  end

  it "spans seven days" do
    expect(week).to have_attributes(ends_on: Date.new(2026, 11, 22), label: "Nov 16 – Nov 22, 2026")
    expect(week.ends_before).to eq(Time.zone.parse("2026-11-23 00:00"))
  end

  it "selects the posts published within the week" do
    inside = create_post(posted_at: Time.zone.parse("2026-11-22 23:59"))
    create_post(posted_at: Time.zone.parse("2026-11-23 00:00"))
    create_post(posted_at: Time.zone.parse("2026-11-15 23:59"))

    expect(week.posts).to contain_exactly(inside)
  end

  it "is complete once its last day has passed" do
    expect(week.complete?(Date.new(2026, 11, 22))).to be(false)
    expect(week.complete?(Date.new(2026, 11, 23))).to be(true)
  end

  describe ".with_posts" do
    it "lists the weeks that have posts, newest first" do
      create_post(posted_at: Time.zone.parse("2026-11-03 10:00"))
      create_post(posted_at: Time.zone.parse("2026-11-17 10:00"))
      create_post(posted_at: Time.zone.parse("2026-11-18 10:00"))

      expect(described_class.with_posts.map(&:starts_on)).to eq([ Date.new(2026, 11, 16), Date.new(2026, 11, 2) ])
    end
  end

  describe ".most_recent_complete" do
    it "skips the week still in progress" do
      travel_to(Time.zone.parse("2026-11-24 12:00")) do
        create_post(posted_at: Time.zone.parse("2026-11-24 09:00"))
        create_post(posted_at: Time.zone.parse("2026-11-18 09:00"))

        expect(described_class.most_recent_complete.starts_on).to eq(Date.new(2026, 11, 16))
      end
    end

    it "falls back to the current week when it is the only one with posts" do
      travel_to(Time.zone.parse("2026-11-24 12:00")) do
        create_post(posted_at: Time.zone.parse("2026-11-24 09:00"))

        expect(described_class.most_recent_complete.starts_on).to eq(Date.new(2026, 11, 23))
      end
    end
  end
end
