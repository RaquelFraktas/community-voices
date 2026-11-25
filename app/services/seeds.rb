# A snapshot of real data (posts, embedded chunks, themes and reports) that loads without Ollama or the
# network, so a fresh clone has something to show.
module Seeds
  DEFAULT_PATH = Rails.root.join("db/seeds/community_voices.json.gz")
  FORMAT_VERSION = 1
  WINDOW_WEEKS = 6
end
