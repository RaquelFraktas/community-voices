# A Monday-to-Sunday week, identified by the date it starts on.
Week = Data.define(:starts_on) do
  def self.containing(date_or_time)
    new(starts_on: date_or_time.to_date.beginning_of_week)
  end

  def self.parse(iso_date)
    containing(Date.iso8601(iso_date.to_s))
  end

  def self.with_posts
    post_counts.keys.sort_by(&:starts_on).reverse
  end

  def self.post_counts
    Post.group(Arel.sql("date_trunc('week', posted_at)::date")).count.transform_keys { |date| new(starts_on: date) }
  end

  def self.most_recent_complete
    with_posts.find(&:complete?) || with_posts.first
  end

  def self.last_complete(today = Date.current)
    containing(today - 7.days)
  end

  def initialize(starts_on:)
    super(starts_on: starts_on.to_date.beginning_of_week)
  end

  def ends_on
    starts_on + 6.days
  end

  def starts_at
    starts_on.beginning_of_day
  end

  def ends_before
    (starts_on + 7.days).beginning_of_day
  end

  def complete?(today = Date.current)
    ends_on < today
  end

  def posts
    Post.posted_between(starts_at, ends_before)
  end

  def label
    "#{starts_on.strftime('%b %-d')} – #{ends_on.strftime('%b %-d, %Y')}"
  end

  def to_param
    starts_on.iso8601
  end
end
