require "rails_helper"

RSpec.describe Reports::Generator do
  let(:week) { Week.new(Date.new(2026, 11, 16)) }
  let(:chat_client) { Llm::FakeChatClient.new(response: "## Summary\nRails 8.1.2 shipped [1].") }
  let(:retriever) { Reports::ContextRetriever.new(search: Search::SimilarChunks.new(client: Embeddings::FakeClient.new)) }
  let(:rag_generator) { Reports::RagGenerator.new(chat_client: chat_client, retriever: retriever) }
  let(:baseline_generator) { Reports::BaselineGenerator.new(chat_client: chat_client) }
  let!(:chunk) do
    post = create_post(title: "Rails 8.1.2 released", posted_at: Time.zone.parse("2026-11-17 09:00"))
    create_chunk(post: post, content: "Rails 8.1.2 released\n\nRails 8.1.2 is out with bug fixes.")
  end

  def new_report(variant)
    Report.create!(week_of: week.starts_on, variant: variant)
  end

  it "picks the generator for the report's variant" do
    expect(described_class.for(new_report(:rag))).to be_a(Reports::RagGenerator)
    expect(described_class.for(new_report(:baseline))).to be_a(Reports::BaselineGenerator)
  end

  shared_examples "a report generator" do |variant|
    let(:report) { new_report(variant) }

    it "is generating while it waits for the LLM, then complete" do
      status_during_call = nil
      allow(chat_client).to receive(:complete).and_wrap_original do |original, **prompt|
        status_during_call = report.reload.status
        original.call(**prompt)
      end

      generator.generate(report)

      expect(status_during_call).to eq("generating")
      expect(report.reload).to be_complete
    end

    it "saves the body, the full prompt, the model name and the timing" do
      generator.generate(report)

      expect(report.reload).to have_attributes(
        body: "## Summary\nRails 8.1.2 shipped [1].", llm_model: "fake-chat", error_message: nil
      )
      expect(report.prompt).to start_with("SYSTEM:\n").and include("USER:\n", week.label)
      expect(report.generation_seconds).to be >= 0
    end

    it "returns the report" do
      expect(generator.generate(report)).to eq(report)
    end

    context "when the LLM fails" do
      before do
        allow(chat_client).to receive(:complete)
          .and_raise(Llm::UnavailableError, "Ollama is not reachable. Start it with: ollama serve")
      end

      it "marks the report failed and saves the error message" do
        expect(generator.generate(report)).to be_failed
        expect(report.reload.error_message).to eq("Llm::UnavailableError: Ollama is not reachable. Start it with: ollama serve")
      end

      it "keeps the prompt that was sent, for debugging" do
        generator.generate(report)

        expect(report.reload.prompt).to include(week.label)
      end

      it "saves no retrievals" do
        generator.generate(report)

        expect(report.retrievals).to be_empty
      end
    end

    it "clears the error of an earlier failed attempt" do
      report.update!(status: :failed, error_message: "earlier failure")

      generator.generate(report)

      expect(report.reload).to have_attributes(status: "complete", error_message: nil)
    end
  end

  describe Reports::RagGenerator do
    let(:generator) { rag_generator }

    it_behaves_like "a report generator", :rag

    it "puts the numbered context in the prompt" do
      generator.generate(new_report(:rag))

      expect(chat_client.prompts.sole[:user]).to include("[1] \"Rails 8.1.2 released\"", "Rails 8.1.2 is out")
    end

    it "saves the retrievals with snapshots of what was retrieved" do
      report = new_report(:rag)
      generator.generate(report)

      expect(report.retrievals.sole).to have_attributes(
        chunk_id: chunk.id, rank: 1, content_snapshot: chunk.content,
        post_title_snapshot: "Rails 8.1.2 released", post_url_snapshot: chunk.post.url
      )
      expect(chunk.reload.retrievals_count).to eq(1)
    end

    it "saves the retrievals in the same transaction as the completed report" do
      report = new_report(:rag)
      allow(report).to receive(:update!).and_call_original
      allow(report).to receive(:update!).with(hash_including(status: :complete)).and_raise(ActiveRecord::RecordInvalid)

      generator.generate(report)

      expect(report.retrievals.reload).to be_empty
      expect(chunk.reload.retrievals_count).to eq(0)
      expect(report.reload).to be_failed
    end
  end

  describe Reports::BaselineGenerator do
    let(:generator) { baseline_generator }

    it_behaves_like "a report generator", :baseline

    it "leaves the context out of the prompt but keeps the week's dates" do
      generator.generate(new_report(:baseline))

      prompt = chat_client.prompts.sole[:user]
      expect(prompt).to include("No forum excerpts are provided", week.label)
      expect(prompt).not_to include("Rails 8.1.2 is out")
    end

    it "saves no retrievals" do
      report = new_report(:baseline)
      generator.generate(report)

      expect(report.retrievals).to be_empty
    end
  end
end
