module Chunking
  # Packs paragraphs into pieces of at most max_length characters. Each piece after the first starts
  # with the last overlap_length characters of the previous one, cut at a word boundary.
  class TextSplitter
    PARAGRAPH_BREAK = /\n\s*\n/
    PARAGRAPH_SEPARATOR = "\n\n".freeze

    def initialize(max_length:, overlap_length:)
      raise ArgumentError, "overlap_length must be shorter than half of max_length" if overlap_length * 2 >= max_length

      @max_length = max_length
      @overlap_length = overlap_length
    end

    def split(text)
      paragraphs_within_limit(text).each_with_object([]) do |paragraph, pieces|
        if pieces.empty?
          pieces << paragraph.dup
        elsif fits?(pieces.last, paragraph)
          pieces.last << PARAGRAPH_SEPARATOR << paragraph
        else
          pieces << join(overlap_from(pieces.last), paragraph)
        end
      end
    end

    private

    def paragraphs_within_limit(text)
      text.split(PARAGRAPH_BREAK).map(&:strip).reject(&:empty?).flat_map { |paragraph| hard_split(paragraph) }
    end

    def hard_split(paragraph)
      slices = []
      rest = paragraph
      while rest.length > paragraph_limit
        cut = word_boundary_before(rest, paragraph_limit)
        slices << rest[0...cut].strip
        rest = rest[cut..].strip
      end
      slices << rest
    end

    def word_boundary_before(text, limit)
      boundary = text.rindex(/\s/, limit)
      boundary&.positive? ? boundary : limit
    end

    def paragraph_limit
      @max_length - @overlap_length - PARAGRAPH_SEPARATOR.length
    end

    def fits?(piece, paragraph)
      piece.length + PARAGRAPH_SEPARATOR.length + paragraph.length <= @max_length
    end

    def overlap_from(piece)
      return "" if @overlap_length.zero?
      return piece if piece.length <= @overlap_length

      piece[-@overlap_length..].sub(/\A\S*\s+/, "")
    end

    def join(overlap, paragraph)
      [ overlap, paragraph ].reject(&:empty?).join(PARAGRAPH_SEPARATOR)
    end
  end
end
