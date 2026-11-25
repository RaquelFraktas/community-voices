module Reports
  # The latest RAG and baseline reports for a week, side by side.
  class Comparison
    attr_reader :week, :rag, :baseline

    def self.for(week)
      new(week: week, rag: Report.latest(week, :rag), baseline: Report.latest(week, :baseline))
    end

    def initialize(week:, rag:, baseline:)
      @week = week
      @rag = rag
      @baseline = baseline
    end

    def reports
      [ rag, baseline ].compact
    end

    def requested?
      reports.any?
    end

    def in_progress?
      reports.any?(&:in_progress?)
    end

    def complete?
      reports.size == 2 && reports.all?(&:complete?)
    end

    def retrievals
      rag ? rag.retrievals.to_a : []
    end

    def citation_urls
      retrievals.to_h { |retrieval| [ retrieval.rank, retrieval.post_url_snapshot ] }
    end

    def metrics
      return unless complete?

      ComparisonMetrics.new(rag: rag, baseline: baseline, retrievals: retrievals,
                            post_titles: week.posts.pluck(:title))
    end
  end
end
