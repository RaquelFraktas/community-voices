require "fugit"

module WeeklyPipeline
  # Reads the weekly pipeline's schedule from config/recurring.yml, the same file Solid Queue schedules from.
  class Schedule
    TASK_KEY = :weekly_pipeline

    def initialize(environment: Rails.env)
      @environment = environment
    end

    def description
      task&.fetch(:schedule)
    end

    def next_run_at(now = Time.current)
      Fugit.parse(description)&.next_time(now)&.to_t&.in_time_zone if description
    end

    private

    def task
      Rails.application.config_for(:recurring, env: @environment)&.dig(TASK_KEY)
    end
  end
end
