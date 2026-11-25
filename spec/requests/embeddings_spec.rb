require "rails_helper"

RSpec.describe "Embeddings", type: :request do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }

  context "when the week has themes" do
    let!(:clustering) do
      create_themed_chunks(week: week, titles_by_group: [ "Zero-downtime migrations", "ActiveStorage CDN", "Kamal deploys" ])
      older = create_chunk(post: create_post(title: "Kamal deploys", posted_at: week.starts_at - 1.week + 1.day))
      older.update!(embedding: Chunk.joins(:post).find_by!(posts: { title: "Kamal deploys" }).embedding)
      Themes::Builder.new.build(week)
    end

    describe "GET /embeddings" do
      it "shows the map with a legend of cluster labels and trend badges" do
        get embeddings_path(week_of: "2026-11-18")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-controller="embedding-map"', embeddings_path(week_of: "2026-11-16", format: :json))
        clustering.clusters.each { |cluster| expect(response.body).to include(cluster.label) }
        expect(response.body).to include("badge--trend-")
      end
    end

    describe "GET /embeddings.json" do
      def points_json
        get embeddings_path(week_of: "2026-11-16", format: :json)
        response.parsed_body
      end

      it "returns every cluster with its label, color and trend" do
        clusters = points_json["clusters"]

        expect(clusters.pluck("label")).to match_array(clustering.clusters.map(&:label))
        expect(clusters.pluck("color")).to all(match(/\A#\h{6}\z/))
        expect(clusters.pluck("trend")).to all(be_in(Themes::TrendAnalyzer::CLASSIFICATIONS))
      end

      it "returns a point for every chunk, and points for every cluster" do
        body = points_json

        expect(body["points"].size).to eq(13)
        expect(body["points"].pluck("cluster_id").uniq).to match_array(body["clusters"].pluck("id"))
      end

      it "gives each point its position, post, cluster label, retrieval count and week" do
        point = points_json["points"].find { |candidate| candidate["title"] == "Kamal deploys" && !candidate["in_report_week"] }

        expect(point).to include("x" => a_kind_of(Float), "y" => a_kind_of(Float), "url" => a_string_starting_with("https://"),
                                 "retrievals_count" => 0, "posted_on" => "2026-11-10")
        expect(point["cluster_label"]).to include("kamal")
      end

      it "marks which points are from the report week" do
        expect(points_json["points"].count { |point| point["in_report_week"] }).to eq(12)
      end
    end
  end

  context "when the week has no themes" do
    it "explains how to build them" do
      get embeddings_path(week_of: "2026-11-16")

      expect(response.body).to include("No themes for this week yet", "themes:build[2026-11-16]")
    end

    it "returns 404 from the JSON endpoint" do
      get embeddings_path(week_of: "2026-11-16", format: :json)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "No themes for this week yet")
    end
  end

  it "rejects a malformed week" do
    get embeddings_path(week_of: "soon")

    expect(response).to have_http_status(:bad_request)
  end
end
