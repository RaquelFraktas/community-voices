module Reports
  # What a retriever hands the generator: the numbered Reports::ContextEntry values for the prompt, and the
  # matching unsaved Retrieval attributes to store alongside the report.
  RetrievalResult = Data.define(:entries, :retrieval_attributes) do
    def self.empty
      new(entries: [], retrieval_attributes: [])
    end
  end
end
