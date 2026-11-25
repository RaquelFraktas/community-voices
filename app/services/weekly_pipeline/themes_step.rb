module WeeklyPipeline
  # Builds the week's themes, unless the week already has them.
  class ThemesStep
    def name = "themes"

    def initialize(builder: Themes::Builder.new)
      @builder = builder
    end

    def call(week, force: false)
      existing = Clustering.latest_for(week)
      return "Skipped: #{week.label} already has #{existing.k} themes (pass force to rebuild)." if existing && !force

      clustering = @builder.build(week)
      "Built #{clustering.k} themes from #{clustering.memberships.count} chunks."
    end
  end
end
