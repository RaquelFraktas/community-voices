module Reports
  # Compares a RAG report with its baseline. Pure Ruby: reports respond to #body and #generation_seconds,
  # retrievals to #rank, #post_url_snapshot and #post_title_snapshot, and post_titles are the week's titles.
  class ComparisonMetrics
    VARIANTS = %i[rag baseline].freeze
    CITATION = /\[(\d+(?:\s*,\s*\d+)*)\]/
    CITATION_GROUP = /#{CITATION}(?:[ \t]*,?[ \t]*#{CITATION})*/
    # A sentence ending in [1][2]…[12] cites everything and supports nothing, so each run of adjacent
    # citations counts for at most this many sources. The prompt asks for the same limit.
    MAX_CITATIONS_PER_GROUP = 3
    WORD = /[[:alnum:]]+(?:['’.][[:alnum:]]+)*/
    WORD_ENDING = /(?:ing|ed|es|s)\z/
    MIN_STEMMABLE_LENGTH = 5
    TITLE_WORD_SHARE = 0.8
    MIN_TITLE_WORDS_FOR_FUZZY_MATCH = 3
    STOP_WORDS = %w[
      a an and are as at be but by can do does for from how in into is it of on or that the this to use
      using what when why with you your
    ].to_set.freeze

    Row = Data.define(:label, :rag, :baseline)

    def initialize(rag:, baseline:, retrievals:, post_titles:)
      @reports = { rag: rag, baseline: baseline }
      @sources = { rag: retrievals.index_by(&:rank), baseline: {} }
      @post_titles = post_titles.uniq
    end

    def rows
      [
        row("Distinct posts cited") { |variant| distinct_posts_cited(variant).size },
        Row.new("Context entries", @sources[:rag].size, @sources[:baseline].size),
        row("Valid citations") { |variant| valid_citations(variant).size },
        row("Invalid citations") { |variant| invalid_citations(variant).size },
        row("Post titles mentioned (of #{@post_titles.size})") { |variant| titles_mentioned(variant).size },
        row("Words") { |variant| word_count(variant) },
        row("Generation time (s)") { |variant| generation_seconds(variant) }
      ]
    end

    def citations(variant)
      citation_groups(variant).flat_map { |group| group.first(MAX_CITATIONS_PER_GROUP) }
    end

    def citation_groups(variant)
      body(variant).to_enum(:scan, CITATION_GROUP).map { Regexp.last_match[0].scan(/\d+/).map(&:to_i).uniq }
    end

    def valid_citations(variant)
      citations(variant).select { |number| @sources[variant].key?(number) }
    end

    def invalid_citations(variant)
      citations(variant).reject { |number| @sources[variant].key?(number) }
    end

    def distinct_posts_cited(variant)
      valid_citations(variant).map { |number| @sources[variant][number].post_url_snapshot }.uniq
    end

    def titles_mentioned(variant)
      lines = body(variant).lines.map { |line| normalize(line) }
      @post_titles.select { |title| title_mentioned?(normalize(title), lines) }
    end

    def word_count(variant)
      body(variant).gsub(CITATION, " ").scan(WORD).size
    end

    def generation_seconds(variant)
      @reports[variant].generation_seconds&.round(1)
    end

    private

    def row(label)
      Row.new(label, *VARIANTS.map { |variant| yield(variant) })
    end

    def body(variant)
      @reports[variant].body.to_s
    end

    def title_mentioned?(title, lines)
      lines.any? { |line| line.include?(title) || mostly_shares_words?(title, line) }
    end

    def mostly_shares_words?(title, line)
      title_words = significant_words(title)
      return false if title_words.size < MIN_TITLE_WORDS_FOR_FUZZY_MATCH

      shared = title_words & significant_words(line)
      shared.size >= (title_words.size * TITLE_WORD_SHARE).ceil
    end

    def significant_words(text)
      text.split.reject { |word| STOP_WORDS.include?(word) || word.length < 2 }.map { |word| stem(word) }.uniq
    end

    def stem(word)
      word.length >= MIN_STEMMABLE_LENGTH ? word.sub(WORD_ENDING, "") : word
    end

    def normalize(text)
      text.downcase.gsub(/[^[:alnum:]]+/, " ").squish
    end
  end
end
