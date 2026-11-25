module Status
  class DatabaseCheck
    NAME = "Postgres".freeze

    def call
      version = ActiveRecord::Base.connection.select_value("SHOW server_version")
      Result.passed(NAME, "PostgreSQL #{version} on port #{ActiveRecord::Base.connection_db_config.configuration_hash[:port]}")
    rescue ActiveRecord::ActiveRecordError => error
      Result.failed(NAME, error.message.lines.first.strip, fix: "docker compose up -d")
    end
  end
end
