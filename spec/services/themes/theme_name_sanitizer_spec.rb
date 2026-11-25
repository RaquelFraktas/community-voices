require "rails_helper"

RSpec.describe Themes::ThemeNameSanitizer do
  subject(:sanitizer) { described_class.new }

  {
    "Database migrations in production" => "Database migrations in production",
    "  Kamal deploy failures  \n" => "Kamal deploy failures",
    "\"ActiveStorage CDN caching\"" => "ActiveStorage CDN caching",
    "Theme: Hotwire and Turbo." => "Hotwire and Turbo",
    "Theme name: **Solid Queue jobs**" => "Solid Queue jobs",
    "- Rails upgrade paths" => "Rails upgrade paths",
    "1. Value objects" => "Value objects",
    "Rails 8.1 upgrades\nThis theme covers upgrades." => "Rails 8.1 upgrades",
    "`composed_of` limitations" => "composedof limitations"
  }.each do |reply, expected|
    it "turns #{reply.inspect} into #{expected.inspect}" do
      expect(sanitizer.sanitize(reply)).to eq(expected)
    end
  end

  it "keeps at most four words" do
    expect(sanitizer.sanitize("Testing database migrations before production deploys")).to eq("Testing database migrations before")
  end

  it "keeps names within 40 characters, cutting at a word boundary" do
    name = sanitizer.sanitize("Internationalization and localization configuration")

    expect(name).to eq("Internationalization and localization")
    expect(name.length).to be <= described_class::MAX_LENGTH
  end

  [
    [ "an empty reply", "" ],
    [ "a blank reply", " \n \n" ],
    [ "nil", nil ],
    [ "punctuation only", "?!..." ],
    [ "a refusal", "I'm sorry, I can't name this theme." ],
    [ "a preamble", "Here is a name for the theme" ],
    [ "a full sentence", "The community spent this week discussing how to run migrations safely in production" ],
    [ "a Markdown document", "## Summary\nA quiet week on the forum." ]
  ].each do |description, reply|
    it "rejects #{description}" do
      expect(sanitizer.sanitize(reply)).to be_nil
    end
  end
end
