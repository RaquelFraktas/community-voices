class Report < ApplicationRecord
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
    pending? || generating?
  end

  def generate_later
    GenerateReportJob.perform_later(id)
  end
end
