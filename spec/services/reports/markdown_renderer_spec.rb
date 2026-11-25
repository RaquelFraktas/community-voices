require "rails_helper"

RSpec.describe Reports::MarkdownRenderer do
  subject(:renderer) { described_class.new(citation_urls: { 1 => "https://forum.test/t/1", 2 => "https://forum.test/t/2" }) }

  it "renders markdown" do
    html = renderer.render("## Summary\n\n- **Busy** week")

    expect(html).to include("<h2>Summary</h2>", "<li><strong>Busy</strong> week</li>")
  end

  it "leaves out anything the model wrote before the first section" do
    html = renderer.render("## Community Voices Document\nWeek: Nov 9 – Nov 15, 2026\n\n## Summary\nBusy week.")

    expect(html).not_to include("Community Voices Document", "Week:")
    expect(html).to include("<h2>Summary</h2>", "Busy week.")
  end

  it "keeps the whole answer when it has no Summary section" do
    expect(renderer.render("Week: Nov 9\n\nNo sections here.")).to include("Week: Nov 9", "No sections here.")
  end

  it "escapes HTML written by the model" do
    html = renderer.render("Hello <script>alert(1)</script> <a href=\"javascript:x\">x</a>")

    expect(html).not_to include("<script>", "javascript:x\">")
    expect(html).to include("&lt;script&gt;")
  end

  it "links each citation to its source post" do
    expect(renderer.render("Upgrades [1][2]."))
      .to include('[<a href="https://forum.test/t/1" class="citation"', '[<a href="https://forum.test/t/2" class="citation"')
  end

  it "links every number in a citation list" do
    html = renderer.render("Upgrades [1, 2].")

    expect(html.scan('class="citation"').size).to eq(2)
  end

  it "marks citations without a source as invalid" do
    expect(renderer.render("Made up [7]."))
      .to include('[<span class="citation citation--invalid" title="No source with this number">7</span>]')
  end

  it "returns HTML that is safe to output" do
    expect(renderer.render("text")).to be_html_safe
  end

  it "renders a missing body as empty" do
    expect(renderer.render(nil)).to eq("")
  end
end
