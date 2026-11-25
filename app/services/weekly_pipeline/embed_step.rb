module WeeklyPipeline
  # Embeds chunks that have no embedding yet, so reruns embed nothing.
  class EmbedStep
    def name = "embed"

    def call(_week, force: false)
      "Embedded #{Embeddings::PendingEmbedder.new.embed_pending} chunks."
    end
  end
end
