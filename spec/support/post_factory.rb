module PostFactory
  def create_post(title: "Upgrading to Rails 8", body: "A body long enough to be worth chunking and embedding.",
                  posted_at: 1.day.ago, source_id: SecureRandom.uuid)
    Post.create!(
      source: "test", source_id: source_id, title: title, body: body,
      author: "matz", url: "https://example.com/#{source_id}", posted_at: posted_at
    )
  end
end

RSpec.configure { |config| config.include PostFactory }
