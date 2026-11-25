require "rails_helper"

RSpec.describe "Retrieval stats", type: :request do
  it "shows the most-retrieved chunks, posts and themes" do
    week = Week.new(Date.new(2026, 11, 16))
    clustering = Clustering.create!(window_start: week.starts_on - 5.weeks, window_end: week.ends_on, k: 3, random_seed: 42)
    report = Report.create!(week_of: week.starts_on, variant: :rag, clustering: clustering)
    chunk = create_chunk(post: create_post(title: "Kamal deploys hang"), content: "Kamal deploys hang\n\nIt hangs on boot.")
    report.retrievals.create!(retrieval_attributes_for(chunk, rank: 1, query_label: "kamal · deploys"))

    get retrieval_stats_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Most-retrieved chunks", "Most-retrieved posts", "Most-retrieved themes",
                                     "Kamal deploys hang", "It hangs on boot.", "kamal · deploys")
  end

  it "explains when nothing has been retrieved yet" do
    get retrieval_stats_path

    expect(response.body).to include("Nothing retrieved yet")
  end
end
