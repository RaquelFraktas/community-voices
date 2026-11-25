# Runs the weekly pipeline for the most recent complete week: ingest, chunk, embed, build themes, write reports.
# It only coordinates the steps; each step does its own work and skips what is already done.
class WeeklyPipelineJob < ApplicationJob
  class StepFailed < StandardError; end

  queue_as :default

  def perform(force: false, week_of: nil)
    week = week_of ? Week.parse(week_of) : Week.last_complete
    log "Weekly pipeline for #{week.label}#{' (forced)' if force}"
    WeeklyPipeline.steps.map { |step| run(step, week, force) }
  end

  private

  def run(step, week, force)
    summary = "#{step.name}: #{step.call(week, force: force)}"
    log summary
    summary
  rescue StandardError => error
    message = "Weekly pipeline stopped at #{step.name}: #{error.message}"
    log message, level: :error
    raise StepFailed, message
  end

  def log(message, level: :info)
    Rails.logger.public_send(level, "[WeeklyPipeline] #{message}")
  end
end
