module Reports
  # What a retriever hands the generator: the numbered Reports::ContextEntry values for the prompt, the
  # matching unsaved Retrieval attributes, and, for theme-based retrieval, the trends and clustering behind them.
  RetrievalResult = Data.define(:entries, :retrieval_attributes, :trends, :clustering) do
    def self.empty
      new(entries: [], retrieval_attributes: [])
    end

    def initialize(entries:, retrieval_attributes:, trends: [], clustering: nil)
      super
    end
  end
end
