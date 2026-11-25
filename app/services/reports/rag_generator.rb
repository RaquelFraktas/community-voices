module Reports
  class RagGenerator < Generator
    def initialize(retriever: ContextRetriever.new, **)
      super(**)
      @retriever = retriever
    end

    private

    def gather_context(week)
      @retriever.retrieve(week)
    end
  end
end
