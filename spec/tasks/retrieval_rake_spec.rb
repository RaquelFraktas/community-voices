require "rails_helper"
require "rake"

RSpec.describe "chunking, embedding and search rake tasks" do
  let(:body) { "We upgraded our app to Rails 8 last week.\n\nThe only surprise was the new default for Solid Queue." }

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  before do
    %w[ingest:discourse chunks:sync embed:pending pipeline:refresh search:similar].each do |name|
      Rake::Task[name].reenable
    end
  end

  def run_task(name, *args)
    expect { Rake::Task[name].invoke(*args) }.to output.to_stdout
  end

  describe "chunks:sync" do
    it "chunks every post and prints created, unchanged and replaced counts" do
      create_post(body: body)

      expect { Rake::Task["chunks:sync"].invoke }
        .to output("Synced chunks for 1 posts: 1 created, 0 unchanged, 0 replaced, 0 deleted.\n").to_stdout
      expect(Chunk.count).to eq(1)
    end
  end

  describe "embed:pending" do
    it "embeds the pending chunks and prints the count" do
      create_post(body: body)
      run_task("chunks:sync")

      expect { Rake::Task["embed:pending"].invoke }.to output("Embedded 1 chunks.\n").to_stdout
      expect(Chunk.pending_embedding).to be_empty
    end

    it "exits with the client's instructions when the embedding service is unavailable" do
      allow(Embeddings).to receive(:client).and_return(Embeddings::OllamaClient.new(base_url: "http://ollama.test/v1"))
      stub_request(:post, "http://ollama.test/v1/embeddings").to_raise(Errno::ECONNREFUSED)
      create_post(body: body)
      run_task("chunks:sync")

      expect { Rake::Task["embed:pending"].invoke }
        .to raise_error(SystemExit).and output(/ollama serve/).to_stderr
    end
  end

  describe "pipeline:refresh" do
    let(:fetched_post) do
      Ingest::FetchedPost.new(
        source: "discourse", source_id: "1", title: "Rails 8 upgrade", body: body,
        author: "dhh", url: "https://example.com/1", posted_at: 1.hour.ago, reply_count: 0
      )
    end

    before do
      allow(Ingest::DiscourseFetcher).to receive(:new)
        .and_return(instance_double(Ingest::DiscourseFetcher, fetch: [ fetched_post ]))
    end

    it "ingests the requested window, then syncs chunks, then embeds them" do
      expect { Rake::Task["pipeline:refresh"].invoke("3") }.to output(<<~OUTPUT).to_stdout
        Fetched 1 posts (1 new). 1 posts stored in total.
        Synced chunks for 1 posts: 1 created, 0 unchanged, 0 replaced, 0 deleted.
        Embedded 1 chunks.
      OUTPUT

      expect(Ingest::DiscourseFetcher).to have_received(:new).with(window: 3.days)
      expect(Chunk.where.not(embedding: nil).count).to eq(1)
    end

    it "defaults to the ingest task's window" do
      run_task("pipeline:refresh")

      expect(Ingest::DiscourseFetcher).to have_received(:new).with(window: 7.days)
    end
  end

  describe "search:similar" do
    it "prints the closest chunks with their post title, distance and the start of their text" do
      create_post(title: "Rails 8 upgrade", body: body)
      run_task("chunks:sync")
      run_task("embed:pending")

      expect { Rake::Task["search:similar"].invoke(Chunk.sole.content) }.to output(<<~OUTPUT).to_stdout
        1. 0.000  Rails 8 upgrade
               #{body.squish.first(100)}
      OUTPUT
    end

    it "explains its usage when no query is given" do
      expect { Rake::Task["search:similar"].invoke }
        .to raise_error(SystemExit).and output(/Usage/).to_stderr
    end
  end
end
