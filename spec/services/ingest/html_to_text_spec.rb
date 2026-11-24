require "rails_helper"

RSpec.describe Ingest::HtmlToText do
  it "strips tags and keeps the text" do
    expect(described_class.call("<p>Use <code>add_index</code> <strong>concurrently</strong></p>"))
      .to eq("Use add_index concurrently")
  end

  it "puts block elements on separate lines" do
    html = "<p>First</p><ul><li>one</li><li>two</li></ul><p>Last</p>"

    expect(described_class.call(html)).to eq("First\none\ntwo\nLast")
  end

  it "decodes HTML entities" do
    expect(described_class.call("<p>Rails &amp; Ruby &lt;3</p>")).to eq("Rails & Ruby <3")
  end

  it "drops quoted replies so text is not duplicated across posts" do
    html = '<aside class="quote"><blockquote><p>earlier post</p></blockquote></aside><p>My reply</p>'

    expect(described_class.call(html)).to eq("My reply")
  end

  it "drops image metadata captions" do
    html = '<div class="lightbox-wrapper"><a><img src="x.png"><div class="meta">image 800×600 30 KB</div></a></div><p>See above</p>'

    expect(described_class.call(html)).to eq("See above")
  end

  it "collapses runs of blank lines" do
    expect(described_class.call("<p>a</p>\n\n\n\n<p>b</p>")).to eq("a\n\nb")
  end

  it "returns an empty string for nil" do
    expect(described_class.call(nil)).to eq("")
  end
end
