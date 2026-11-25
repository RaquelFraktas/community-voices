desc "Check Postgres, pgvector, Ollama and its models, and print the command that fixes anything missing"
task status: :environment do
  overview = Status::Overview.new
  overview.checks.each do |check|
    line = "#{check.ok? ? '✓' : '✗'} #{check.name}: #{check.detail}"
    line += "\n    fix: #{check.fix}" if check.fix
    puts line
  end
  puts "", overview.record_counts.map { |label, count| "#{label}: #{count}" }.join(", ")
  puts "Next weekly pipeline run: #{overview.next_pipeline_run || 'not scheduled in this environment'}"
end
