require "rails_helper"
require "rake"

RSpec.describe "rake themes:build" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  before { Rake::Task["themes:build"].reenable }

  around { |example| travel_to(Time.zone.parse("2026-11-24T12:00:00Z")) { example.run } }

  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  # An abort inside the task raises SystemExit, which would end the whole RSpec run instead of failing.
  def output_of(*args)
    printed = nil
    expect { printed = capture_stdout { Rake::Task["themes:build"].invoke(*args) } }.not_to raise_error
    printed
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  context "with enough chunks" do
    before do
      create_themed_chunks(week: week, titles_by_group: [ "Zero-downtime migrations", "ActiveStorage CDN", "Kamal deploys" ])
    end

    it "builds the themes and prints each one's label, size, weekly counts and trend" do
      printed = output_of("2026-11-16")

      expect(printed).to include("Building themes for Nov 16 – Nov 22, 2026", "3 themes from 12 chunks",
                                 "Oct 12 – Nov 22, 2026", "seed 42", "Theme", "Size", "Weekly (Oct 12 → Nov 16)", "Trend",
                                 "/embeddings?week_of=2026-11-16")
      expect(printed).to match(/deploys · kamal\s+4\s+0 0 0 0 0 4\s+new/)
      expect(Clustering.count).to eq(1)
    end

    it "defaults to the most recent complete week" do
      output_of

      expect(Clustering.sole.window_end).to eq(week.ends_on)
    end
  end

  it "stops with a clear message when there are too few chunks to cluster" do
    create_chunk(post: create_post(posted_at: week.starts_at + 1.day))

    expect { Rake::Task["themes:build"].invoke("2026-11-16") }
      .to raise_error(SystemExit).and output(/Need at least 4 vectors to cluster, got 1/).to_stderr
  end
end
