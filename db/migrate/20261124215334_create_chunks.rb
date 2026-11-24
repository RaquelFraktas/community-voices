class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :post, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :content, null: false
      t.string :content_digest, null: false
      t.vector :embedding, limit: 768
      t.integer :retrievals_count, null: false, default: 0

      t.timestamps
    end

    add_index :chunks, [ :post_id, :position ], unique: true
    add_index :chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
