class Report < ApplicationRecord
  GENERATION_TIMEOUT = 10.minutes

  enum :variant, { rag: "rag", baseline: "baseline" }, validate: true
  enum :status, { pending: "pending", generating: "generating", complete: "complete", failed: "failed" },
       default: :pending, validate: true

  has_many :retrievals, -> { order(:rank) }, dependent: :delete_all, inverse_of: :report

  validates :week_of, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.request_comparison(week)
    transaction { variants.keys.map { |variant| create!(week_of: week.starts_on, variant: variant) } }
  end

  def self.latest(week, variant)
    where(week_of: week.starts_on, variant: variant).newest_first.first
  end

  def week
    Week.new(week_of)
  end

  def in_progress?
    unfinished? && !timed_out?
  end

  # A report whose job died with the server (development runs jobs in-process) stays pending or
  # generating forever. Past the timeout it is treated as failed so it can be retried.
  def timed_out?(now = Time.current)
    unfinished? && persisted? && updated_at < now - GENERATION_TIMEOUT
  end

  def displayed_status
    timed_out? ? "failed" : status
  end

  def failure_message
    return error_message unless timed_out?

    "Timed out: still #{status} after #{GENERATION_TIMEOUT.inspect}, probably because the server " \
      "restarted mid-generation."
  end

  def retryable?
    failed? || timed_out?
  end

  def retry_later
    update!(status: :pending, error_message: nil)
    generate_later
  end

  def generate_later
    GenerateReportJob.perform_later(id)
  end

  private

  def unfinished?
    pending? || generating?
  end
end
