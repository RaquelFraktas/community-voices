# Loads a snapshot of real forum data with precomputed embeddings, themes and reports, so every page works
# right after setup without Ollama or the network. Safe to run again: records are matched on natural keys.
# Regenerate the snapshot from your own data with: bin/rails seeds:export

if Seeds::DEFAULT_PATH.exist?
  puts Seeds::Importer.new.import(Seeds::DEFAULT_PATH)
else
  puts "No seed snapshot at #{Seeds::DEFAULT_PATH.relative_path_from(Rails.root)}; skipping."
end
