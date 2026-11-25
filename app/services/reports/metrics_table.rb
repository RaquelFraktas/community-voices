module Reports
  # Formats ComparisonMetrics rows as a plain-text table for the terminal.
  class MetricsTable
    HEADERS = [ "Metric", "RAG", "Baseline" ].freeze

    def initialize(metrics)
      @metrics = metrics
    end

    def to_s
      lines = [ HEADERS, *@metrics.rows.map { |row| [ row.label, row.rag.to_s, row.baseline.to_s ] } ]
      widths = lines.transpose.map { |column| column.map(&:length).max }
      lines.map { |cells| format_line(cells, widths) }.insert(1, separator(widths)).join("\n")
    end

    private

    def format_line(cells, widths)
      label, *values = cells
      ([ label.ljust(widths.first) ] + values.zip(widths.drop(1)).map { |value, width| value.rjust(width) }).join("  ")
    end

    def separator(widths)
      widths.map { |width| "-" * width }.join("  ")
    end
  end
end
