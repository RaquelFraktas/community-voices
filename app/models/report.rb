class Report < ApplicationRecord
  DEFAULT_GENERATION_TIMEOUT_MINUTES = 10

  enum :variant, { rag: "rag", baseline: "baseline" }, validate: true
  enum :status, { pending: "pending", generating: "generating", complete: "complete", failed: "failed" },
       default: :pending, validate: true

  has_many :retrievals, -> { order(:rank) }, dependent: :delete_all, inverse_of: :report
  belongs_to :clustering, optional: true

  validates :week_of, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.request_comparison(week)
    transaction { variants.keys.map { |variant| create!(week_of: week.starts_on, variant: variant) } }
  end

  def self.latest(week, variant)
    where(week_of: week.starts_on, variant: variant).newest_first.first
  end

  def self.generation_timeout
    Integer(ENV.fetch("REPORT_GENERATION_TIMEOUT_MINUTES", DEFAULT_GENERATION_TIMEOUT_MINUTES)).minutes
  end

  def week
    Week.new(week_of)
  end

  def in_progress?
    unfinished? && !timed_out?
  end

  # A report whose job never finished (the worker crashed, or the model hung) stays pending or generating
  # forever. Past the timeout it is treated as failed so it can be retried.
  def timed_out?(now = Time.current)
    unfinished? && persisted? && updated_at < now - self.class.generation_timeout
  end

  def displayed_status
    timed_out? ? "failed" : status
  end

  def failure_message
    return error_message unless timed_out?

    "Timed out: still #{status} after #{self.class.generation_timeout.inspect}, probably because the job " \
      "worker stopped mid-generation."
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
