module ThemesFactory
  # Creates embedded chunks in the given week whose embeddings form one tight synthetic group per title.
  def create_themed_chunks(week:, titles_by_group:, per_group: 4, seed: 3)
    points = separated_groups(groups: titles_by_group.size, per_group: per_group, seed: seed)
    points.each_with_index.map do |point, index|
      title = titles_by_group[point[:group]]
      chunk = create_chunk(post: create_post(title: title, posted_at: week.starts_at + (index % 7).days),
                           content: "#{title}\n\nChunk #{index}")
      chunk.tap { chunk.update!(embedding: point[:vector]) }
    end
  end
end

RSpec.configure { |config| config.include ThemesFactory }
