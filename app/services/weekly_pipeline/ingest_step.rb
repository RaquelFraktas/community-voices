module WeeklyPipeline
  # Fetches every forum post from the start of the week until now. Posts are upserted, so reruns add nothing.
  class IngestStep
    def name = "ingest"

    def initialize(fetcher_for: ->(window) { Ingest::DiscourseFetcher.new(window: window) })
      @fetcher_for = fetcher_for
    end

    def call(week, force: false)
      Ingest::Pipeline.new(fetcher: @fetcher_for.call(window_reaching(week))).run.to_s
    end

    private

    def window_reaching(week)
      ((Time.current - week.starts_at) / 1.day).ceil.days
    end
  end
end
