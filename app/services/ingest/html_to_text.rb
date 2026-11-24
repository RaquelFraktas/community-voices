module Ingest
  class HtmlToText
    BLOCK_ELEMENTS = %w[p div li pre blockquote br tr h1 h2 h3 h4 h5 h6].freeze
    NOISE_SELECTORS = [ "aside.quote", ".lightbox-wrapper .meta" ].freeze

    def self.call(html)
      new(html).text
    end

    def initialize(html)
      @fragment = Nokogiri::HTML5.fragment(html.to_s)
    end

    def text
      remove_noise
      separate_blocks
      normalize_whitespace(@fragment.text)
    end

    private

    def remove_noise
      @fragment.css(*NOISE_SELECTORS).each(&:remove)
    end

    def separate_blocks
      @fragment.css(*BLOCK_ELEMENTS).each { |element| element.add_next_sibling("\n") }
    end

    def normalize_whitespace(text)
      text.lines.map { |line| line.squish }.join("\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
