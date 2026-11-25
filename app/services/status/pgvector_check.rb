module Status
  # pgvector must be 0.8 or newer for the iterative HNSW scans that keep filtered searches complete.
  class PgvectorCheck
    NAME = "pgvector".freeze
    MINIMUM_VERSION = Gem::Version.new("0.8.0")

    def call
      version = installed_version
      return Result.failed(NAME, "extension not installed", fix: "bin/rails db:prepare") unless version
      return Result.passed(NAME, "version #{version}") if Gem::Version.new(version) >= MINIMUM_VERSION

      Result.failed(NAME, "version #{version}, need #{MINIMUM_VERSION}+", fix: "Use the pgvector/pgvector:pg17 image: docker compose up -d")
    rescue ActiveRecord::ActiveRecordError => error
      Result.failed(NAME, error.message.lines.first.strip, fix: "docker compose up -d")
    end

    private

    def installed_version
      ActiveRecord::Base.connection.select_value("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
    end
  end
end
