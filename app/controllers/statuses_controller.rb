class StatusesController < ApplicationController
  def show
    @overview = Status::Overview.new
  end
end
