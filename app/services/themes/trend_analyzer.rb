module Themes
  # Compares each cluster's share of this week's chunks with its average share in the earlier weeks of the
  # window (momentum), and classifies it as rising, steady, fading or new. Weeks without any chunks, such as
  # weeks before ingestion started, are left out of the average.
  class TrendAnalyzer
    RISING_MOMENTUM = 1.5
    FADING_MOMENTUM = 0.67
    CLASSIFICATIONS = %w[new rising steady fading].freeze

    ClusterSample = Data.define(:cluster_id, :label, :member_weeks)

    Trend = Data.define(:cluster_id, :label, :weekly_counts, :momentum, :classification) do
      def this_week_count
        weekly_counts.values.last
      end

      def emerging?
        %w[new rising].include?(classification)
      end
    end

    def analyze(samples, weeks:)
      totals = weeks.index_with { |week| samples.sum { |sample| sample.member_weeks.count(week) } }
      samples.map { |sample| trend_for(sample, weeks, totals) }
    end

    private

    def trend_for(sample, weeks, totals)
      counts = weeks.index_with { |week| sample.member_weeks.count(week) }
      momentum = momentum_for(counts, totals, weeks)
      Trend.new(cluster_id: sample.cluster_id, label: sample.label, weekly_counts: counts, momentum: momentum,
                classification: classify(counts, weeks, momentum))
    end

    def momentum_for(counts, totals, weeks)
      earlier_shares = weeks[0...-1].select { |week| totals[week].positive? }.map { |week| share(counts, totals, week) }
      average = earlier_shares.sum / earlier_shares.size if earlier_shares.any?
      return if average.nil? || average.zero?

      (share(counts, totals, weeks.last) / average).round(2)
    end

    def share(counts, totals, week)
      totals[week].positive? ? counts[week].fdiv(totals[week]) : 0.0
    end

    def classify(counts, weeks, momentum)
      this_week = counts[weeks.last]
      earlier = counts.values_at(*weeks[0...-1]).sum
      return "new" if earlier.zero? && this_week.positive?
      return "fading" if this_week.zero? || momentum.to_f <= FADING_MOMENTUM
      return "rising" if momentum.to_f >= RISING_MOMENTUM

      "steady"
    end
  end
end
