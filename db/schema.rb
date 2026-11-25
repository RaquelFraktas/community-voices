# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_24_223526) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "chunks", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.integer "position", null: false
    t.text "content", null: false
    t.string "content_digest", null: false
    t.vector "embedding", limit: 768
    t.integer "retrievals_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["post_id", "position"], name: "index_chunks_on_post_id_and_position", unique: true
  end

  create_table "posts", force: :cascade do |t|
    t.string "source", null: false
    t.string "source_id", null: false
    t.string "title", null: false
    t.text "body", default: "", null: false
    t.string "author"
    t.string "url", null: false
    t.datetime "posted_at", null: false
    t.integer "reply_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["posted_at"], name: "index_posts_on_posted_at"
    t.index ["source", "source_id"], name: "index_posts_on_source_and_source_id", unique: true
  end

  create_table "reports", force: :cascade do |t|
    t.date "week_of", null: false
    t.string "variant", null: false
    t.string "status", default: "pending", null: false
    t.string "llm_model"
    t.text "prompt"
    t.text "body"
    t.text "error_message"
    t.float "generation_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["week_of", "variant", "created_at"], name: "index_reports_on_week_of_and_variant_and_created_at"
  end

  create_table "retrievals", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "chunk_id"
    t.text "content_snapshot", null: false
    t.string "post_title_snapshot", null: false
    t.string "post_url_snapshot", null: false
    t.string "query_label", null: false
    t.integer "rank", null: false
    t.float "distance", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chunk_id"], name: "index_retrievals_on_chunk_id"
    t.index ["report_id", "rank"], name: "index_retrievals_on_report_id_and_rank", unique: true
    t.index ["report_id"], name: "index_retrievals_on_report_id"
  end

  add_foreign_key "chunks", "posts", on_delete: :cascade
  add_foreign_key "retrievals", "chunks", on_delete: :nullify
  add_foreign_key "retrievals", "reports", on_delete: :cascade
end
