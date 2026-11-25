require "rails_helper"

RSpec.describe "Seed snapshot" do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:path) { Rails.root.join("tmp/seeds_spec_#{SecureRandom.hex(4)}.json.gz") }
  let(:exporter) { Seeds::Exporter.new(last_week: week) }

  before do
    create_themed_chunks(week: week, titles_by_group: [ "Zero-downtime migrations", "ActiveStorage CDN", "Kamal deploys" ])
    create_chunk(post: create_post(title: "Older thread", posted_at: week.starts_at - 3.weeks))
    create_chunk(post: create_post(title: "Too old to export", posted_at: week.starts_at - 7.weeks))
    Report.request_comparison(week).each { |report| Reports::Generator.for(report).generate(report) }
  end

  after { FileUtils.rm_f(path) }

  def wipe_database
    [ Retrieval, Report, ClusterMembership, Cluster, Clustering, Chunk, Post ].each(&:delete_all)
  end

  def counts
    [ Post, Chunk, Clustering, Cluster, ClusterMembership, Report, Retrieval ].to_h { |model| [ model.name, model.count ] }
  end

  it "exports the last six weeks of posts, chunks, themes and reports" do
    snapshot = exporter.snapshot

    expect(snapshot[:posts].pluck(:title)).not_to include("Too old to export")
    expect(snapshot[:posts].size).to eq(13)
    expect(snapshot[:chunks].size).to eq(13)
    expect(snapshot[:chunks].first[:embedding].size).to eq(Embeddings::DIMENSIONS)
    expect(snapshot[:clusterings].size).to eq(1)
    expect(snapshot[:reports].map { |report| report[:variant] }).to contain_exactly("rag", "baseline")
  end

  it "writes gzipped JSON" do
    exporter.export(path)

    expect(JSON.parse(Zlib::GzipReader.open(path, &:read))).to include("version" => Seeds::FORMAT_VERSION)
  end

  it "round-trips: importing an export into an empty database gives identical records" do
    exporter.export(path)
    before_export = exporter.snapshot
    before_counts = counts.merge("Post" => 13, "Chunk" => 13)
    wipe_database

    summary = Seeds::Importer.new.import(path)

    expect(Seeds::Exporter.new(last_week: week).snapshot).to eq(before_export)
    expect(counts).to eq(before_counts)
    expect(summary.to_s).to eq("Seeded 13 posts, 13 chunks, 1 clusterings and 2 reports.")
  end

  it "restores what the pages need: embeddings, theme labels and positions, report links and retrieval counts" do
    rag_before = Report.find_by!(variant: :rag)
    retrieved_counts = Chunk.where(retrievals_count: 1..).count
    exporter.export(path)
    wipe_database

    Seeds::Importer.new.import(path)

    rag = Report.find_by!(variant: :rag)
    expect(rag.clustering.clusters.map(&:label)).to all(be_present)
    expect(rag.retrievals.map(&:chunk)).to all(be_present)
    expect(rag.body).to eq(rag_before.body)
    expect(ClusterMembership.where(x: nil)).to be_empty
    expect(Chunk.where(embedding: nil)).to be_empty
    expect(Chunk.where(retrievals_count: 1..).count).to eq(retrieved_counts)
  end

  it "is idempotent: importing twice creates nothing new" do
    exporter.export(path)
    wipe_database
    Seeds::Importer.new.import(path)
    after_first_import = counts

    Seeds::Importer.new.import(path)

    expect(counts).to eq(after_first_import)
    expect(Chunk.sum(:retrievals_count)).to eq(Retrieval.count)
  end

  it "merges into a database that already has the same posts, without duplicating them" do
    exporter.export(path)

    expect { Seeds::Importer.new.import(path) }.not_to(change { counts })
  end
end
