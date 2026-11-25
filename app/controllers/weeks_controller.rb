class WeeksController < ApplicationController
  def index
    @comparisons = Week.with_posts.map { |week| Reports::Comparison.for(week) }
    @post_counts = Week.post_counts
  end
end
