module WeeklyPipeline
  # Chunks new and edited posts. Unchanged chunks are left alone, so reruns write nothing.
  class ChunkStep
    def name = "chunk sync"

    def call(_week, force: false)
      Chunking::ChunkSyncer.new.sync_all.to_s
    end
  end
end
