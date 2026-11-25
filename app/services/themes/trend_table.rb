module Themes
  # Formats a clustering's themes as a plain-text table for the terminal: label, size, weekly counts, trend.
  class TrendTable
    def initialize(clustering)
      @clustering = clustering
    end

    def to_s
      [ summary, "", *table_lines ].join("\n")
    end

    private

    def summary
      "#{@clustering.k} themes from #{@clustering.memberships.count} chunks, " \
        "#{@clustering.window_start.strftime('%b %-d')} – #{@clustering.window_end.strftime('%b %-d, %Y')} " \
        "(silhouette #{@clustering.silhouette_score&.round(2)}, seed #{@clustering.random_seed})"
    end

    def table_lines
      rows = [ headers, *trend_rows ]
      widths = rows.transpose.map { |column| column.map(&:length).max }
      rows.map { |cells| cells.zip(widths).map { |cell, width| cell.ljust(width) }.join("  ").rstrip }
    end

    def headers
      [ "Theme", "Size", "Weekly (#{week_labels})", "Trend" ]
    end

    def trend_rows
      sizes = @clustering.clusters.to_h { |cluster| [ cluster.id, cluster.size ] }
      @clustering.trends.sort_by { |trend| [ -(trend.momentum || Float::INFINITY), trend.label ] }.map do |trend|
        [ trend.label, sizes.fetch(trend.cluster_id).to_s, trend.weekly_counts.values.join(" "), trend_label(trend) ]
      end
    end

    def week_labels
      "#{@clustering.weeks.first.starts_on.strftime('%b %-d')} → #{@clustering.weeks.last.starts_on.strftime('%b %-d')}"
    end

    def trend_label(trend)
      trend.momentum ? "#{trend.classification} (momentum #{trend.momentum})" : trend.classification
    end
  end
end
