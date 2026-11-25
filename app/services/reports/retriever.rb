module Reports
  # Interface for building a report's context. Implementations return a Reports::RetrievalResult for a Week.
  class Retriever
    def retrieve(week)
      raise NotImplementedError, "#{self.class} must implement #retrieve"
    end
  end
end
