module Reports
  # Renders LLM-written markdown as safe HTML (any HTML in the input is escaped) and turns [n] citations
  # into links to their source posts. Citations without a source are marked as invalid.
  class MarkdownRenderer
    include ActionView::Helpers::TagHelper

    CITATION_NUMBER = /\d+/

    def initialize(citation_urls: {})
      @citation_urls = citation_urls
    end

    def render(markdown)
      link_citations(markdown_engine.render(markdown.to_s)).html_safe
    end

    private

    def markdown_engine
      renderer = Redcarpet::Render::HTML.new(escape_html: true, safe_links_only: true, link_attributes: { rel: "noopener" })
      Redcarpet::Markdown.new(renderer, autolink: true, tables: true, no_intra_emphasis: true, lax_spacing: true)
    end

    def link_citations(html)
      html.gsub(ComparisonMetrics::CITATION) do |citation|
        citation.gsub(CITATION_NUMBER) { |number| citation_tag(number.to_i) }
      end
    end

    def citation_tag(number)
      url = @citation_urls[number]
      return tag.span(number, class: "citation citation--invalid", title: "No source with this number") unless url

      tag.a(number, href: url, class: "citation", title: "Source #{number}", target: "_blank", rel: "noopener")
    end
  end
end
