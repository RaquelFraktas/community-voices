module Reports
  # The flow both variants share: generating → build prompt → ask the LLM → complete, or failed with the
  # error. Subclasses only decide which context the prompt gets.
  class Generator
    def self.for(report)
      report.rag? ? RagGenerator.new : BaselineGenerator.new
    end

    def initialize(chat_client: Llm.client, prompt_builder: PromptBuilder.new)
      @chat_client = chat_client
      @prompt_builder = prompt_builder
    end

    def generate(report)
      started = now
      start(report)
      context = gather_context(report.week)
      prompt = prompt_for(report, context)
      body = @chat_client.complete(system: prompt.system, user: prompt.user)
      complete(report, body, context, now - started)
    rescue StandardError => error
      fail(report, error)
    end

    private

    def gather_context(_week)
      raise NotImplementedError, "#{self.class} must implement #gather_context"
    end

    def start(report)
      report.update!(status: :generating, error_message: nil, llm_model: @chat_client.model)
    end

    def prompt_for(report, context)
      @prompt_builder.build(week: report.week, entries: context.entries).tap do |prompt|
        report.update!(prompt: prompt.to_s)
      end
    end

    def complete(report, body, context, seconds)
      Report.transaction(requires_new: true) do
        Retrieval.create!(context.retrieval_attributes.map { |attributes| attributes.merge(report_id: report.id) })
        report.update!(status: :complete, body: body, generation_seconds: seconds)
      end
      report
    end

    def fail(report, error)
      report.update!(status: :failed, error_message: "#{error.class}: #{error.message}")
      report
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
