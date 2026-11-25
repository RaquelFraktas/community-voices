# One k-means run over the embedded chunks of a multi-week window, ending with a report week.
class Clustering < ApplicationRecord
  has_many :clusters, -> { order(:position) }, dependent: :delete_all, inverse_of: :clustering
  has_many :memberships, through: :clusters
  has_many :reports, dependent: :nullify

  validates :window_start, :window_end, :k, :random_seed, presence: true

  def self.latest_for(week)
    where(window_end: week.ends_on).order(created_at: :desc, id: :desc).first
  end

  def report_week
    Week.containing(window_end)
  end

  def weeks
    (window_start..window_end).step(7).map { |date| Week.new(date) }
  end

  def trends
    Themes::TrendAnalyzer.new.analyze(trend_samples, weeks: weeks.map(&:starts_on))
  end

  private

  def trend_samples
    clusters.includes(memberships: { chunk: :post }).map do |cluster|
      member_weeks = cluster.memberships.map { |membership| Week.containing(membership.chunk.post.posted_at).starts_on }
      Themes::TrendAnalyzer::ClusterSample.new(cluster_id: cluster.id, label: cluster.label, member_weeks: member_weeks)
    end
  end
end
