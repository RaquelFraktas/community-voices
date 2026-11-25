module Reports
  class BaselineGenerator < Generator
    private

    def gather_context(_week)
      RetrievalResult.empty
    end
  end
end
