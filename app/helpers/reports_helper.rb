module ReportsHelper
  def report_body_html(report, citation_urls)
    Reports::MarkdownRenderer.new(citation_urls: citation_urls).render(report.body)
  end

  def report_status_badge(report)
    return tag.span("not generated", class: "badge") unless report

    tag.span(report.status, class: "badge badge--#{report.status}")
  end

  def variant_title(variant)
    variant.to_s == "rag" ? "With RAG (forum context)" : "Baseline (no context)"
  end
end
