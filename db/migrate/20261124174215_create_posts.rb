class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :source, null: false
      t.string :source_id, null: false
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.string :author
      t.string :url, null: false
      t.datetime :posted_at, null: false
      t.integer :reply_count, null: false, default: 0

      t.timestamps
    end

    add_index :posts, [ :source, :source_id ], unique: true
    add_index :posts, :posted_at
  end
end
