module Themes
  # Names clusters by their most distinctive title words (TF-IDF): words common in a cluster's post titles but
  # rare across all titles in the window. No LLM involved.
  class Labeler
    TERMS_PER_LABEL = 3
    SEPARATOR = " · ".freeze
    FALLBACK_LABEL = "miscellaneous".freeze
    MIN_TERM_LENGTH = 3
    TERM = /[a-z][a-z0-9]*(?:\.[a-z0-9]+)*/
    STOP_WORDS = %w[
      about after all also and any are back been before being best but can could does doing don for from
      get getting has have help how into its just like make making more need new not now one only other our out
      over should some than that the their them then there these they this those through use used using want way
      what when where which while who why will with without would you your
      app apps application applications issue issues problem problems question questions rails ruby rubyonrails
    ].to_set.freeze

    def label(descriptions, all_titles:)
      weights = inverse_document_frequencies(all_titles)
      descriptions.transform_values { |description| label_for(description.titles, weights) }
    end

    def terms(title)
      title.downcase.scan(TERM).reject { |term| term.length < MIN_TERM_LENGTH || STOP_WORDS.include?(term) }.uniq
    end

    private

    def label_for(titles, weights)
      top_terms = term_counts(titles)
                    .map { |term, count| [ term, count * weights.fetch(term, weights.values.max || 1.0) ] }
                    .sort_by { |term, score| [ -score, term ] }
                    .first(TERMS_PER_LABEL)
                    .map(&:first)
      top_terms.any? ? top_terms.join(SEPARATOR) : FALLBACK_LABEL
    end

    def term_counts(titles)
      titles.flat_map { |title| terms(title) }.tally
    end

    def inverse_document_frequencies(all_titles)
      documents = all_titles.uniq.map { |title| terms(title) }
      document_frequencies = documents.flatten.tally
      document_frequencies.transform_values { |count| Math.log((documents.size + 1.0) / (count + 1.0)) + 1.0 }
    end
  end
end
