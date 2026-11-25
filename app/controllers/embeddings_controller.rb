class EmbeddingsController < ApplicationController
  rescue_from Date::Error, with: :invalid_week

  def show
    @week = Week.parse(params.require(:week_of))
    @clustering = Clustering.latest_for(@week)

    respond_to do |format|
      format.html
      format.json { render_points }
    end
  end

  private

  def render_points
    return render json: { error: "No themes for this week yet" }, status: :not_found unless @clustering

    render json: Themes::EmbeddingMapSerializer.new(@clustering)
  end

  def invalid_week
    render plain: "week_of must be a date like 2026-11-16", status: :bad_request
  end
end
