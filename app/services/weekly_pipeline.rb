# The steps of the weekly run, in order. Each responds to #name and #call(week, force:), returning a
# one-line summary, and is safe to run again for the same week.
module WeeklyPipeline
  def self.steps
    [ IngestStep.new, ChunkStep.new, EmbedStep.new, ThemesStep.new, ReportsStep.new ]
  end
end
