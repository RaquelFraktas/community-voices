class CreateClusterings < ActiveRecord::Migration[8.1]
  def change
    create_table :clusterings do |t|
      t.date :window_start, null: false
      t.date :window_end, null: false
      t.integer :k, null: false
      t.integer :random_seed, null: false
      t.float :silhouette_score

      t.timestamps
    end
    add_index :clusterings, [ :window_end, :created_at ]

    create_table :clusters do |t|
      t.references :clustering, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.string :label, null: false, default: ""
      t.vector :centroid, limit: 768, null: false
      t.integer :size, null: false

      t.timestamps
    end
    add_index :clusters, [ :clustering_id, :position ], unique: true

    create_table :cluster_memberships do |t|
      t.references :cluster, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :chunk, null: false, foreign_key: { on_delete: :cascade }
      t.float :distance_to_centroid, null: false
      t.float :x
      t.float :y

      t.timestamps
    end
    add_index :cluster_memberships, [ :cluster_id, :chunk_id ], unique: true

    add_reference :reports, :clustering, foreign_key: { on_delete: :nullify }
  end
end
