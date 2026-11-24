module Ingest
  # Interface for community sources (Discourse, Reddit, fixtures, ...).
  # Implementations return the Ingest::FetchedPost values published within their time window.
  class Fetcher
    DEFAULT_WINDOW = 7.days

    def fetch
      raise NotImplementedError, "#{self.class} must implement #fetch"
    end
  end
end
