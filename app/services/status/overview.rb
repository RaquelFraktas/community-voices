module Status
  # Everything the status page and `rake status` show: the checks, record counts, the latest week ingested and
  # the next scheduled run of the weekly pipeline.
  class Overview
    def initialize(database_check: DatabaseCheck.new, pgvector_check: PgvectorCheck.new, ollama_check: OllamaCheck.new,
                   schedule: WeeklyPipeline::Schedule.new)
      @database_check = database_check
      @pgvector_check = pgvector_check
      @ollama_check = ollama_check
      @schedule = schedule
    end

    def checks
      @checks ||= begin
        database = @database_check.call
        [ database, (@pgvector_check.call if database.ok?), *@ollama_check.call ].compact
      end
    end

    def all_ok?
      checks.all?(&:ok?)
    end

    def record_counts
      {
        "Posts" => Post.count, "Chunks" => Chunk.count, "Embedded chunks" => Chunk.where.not(embedding: nil).count,
        "Clusterings" => Clustering.count, "Reports" => Report.count, "Retrievals" => Retrieval.count
      }
    end

    def latest_week_ingested
      latest = Post.maximum(:posted_at)
      Week.containing(latest) if latest
    end

    def next_pipeline_run
      @schedule.next_run_at
    end

    def schedule_description
      @schedule.description
    end
  end
end
