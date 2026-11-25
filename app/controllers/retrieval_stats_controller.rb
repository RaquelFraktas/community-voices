class RetrievalStatsController < ApplicationController
  def show
    @stats = RetrievalStatsQuery.new
  end
end
