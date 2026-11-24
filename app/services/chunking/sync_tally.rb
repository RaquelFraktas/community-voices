module Chunking
  SyncTally = Data.define(:posts, :created, :unchanged, :replaced, :deleted) do
    def self.zero
      new
    end

    def initialize(posts: 0, created: 0, unchanged: 0, replaced: 0, deleted: 0)
      super
    end

    def +(other)
      self.class.new(**to_h.merge(other.to_h) { |_count, mine, theirs| mine + theirs })
    end

    def to_s
      "Synced chunks for #{posts} posts: #{created} created, #{unchanged} unchanged, " \
        "#{replaced} replaced, #{deleted} deleted."
    end
  end
end
