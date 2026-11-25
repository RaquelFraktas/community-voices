class CreateReportsAndRetrievals < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.date :week_of, null: false
      t.string :variant, null: false
      t.string :status, null: false, default: "pending"
      t.string :llm_model
      t.text :prompt
      t.text :body
      t.text :error_message
      t.float :generation_seconds

      t.timestamps
    end
    add_index :reports, [ :week_of, :variant, :created_at ]

    create_table :retrievals do |t|
      t.references :report, null: false, foreign_key: { on_delete: :cascade }
      t.references :chunk, foreign_key: { on_delete: :nullify }
      t.text :content_snapshot, null: false
      t.string :post_title_snapshot, null: false
      t.string :post_url_snapshot, null: false
      t.string :query_label, null: false
      t.integer :rank, null: false
      t.float :distance, null: false

      t.timestamps
    end
    add_index :retrievals, [ :report_id, :rank ], unique: true
  end
end
