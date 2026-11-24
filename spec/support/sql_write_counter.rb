module SqlWriteCounter
  WRITE_STATEMENT = /\A\s*(INSERT|UPDATE|DELETE)\b/i

  def count_sql_writes(&block)
    writes = 0
    counter = ->(*, payload) { writes += 1 if payload[:sql].match?(WRITE_STATEMENT) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    writes
  end
end

RSpec.configure { |config| config.include SqlWriteCounter }
