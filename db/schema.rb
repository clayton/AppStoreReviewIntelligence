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

ActiveRecord::Schema[8.0].define(version: 2025_07_23_180253) do
  create_table "analyses", force: :cascade do |t|
    t.string "keyword", null: false
    t.text "llm_analysis"
    t.text "patterns"
    t.text "opportunities"
    t.integer "total_reviews_analyzed"
    t.string "llm_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_analyses_on_created_at"
    t.index ["keyword"], name: "index_analyses_on_keyword"
  end

  create_table "apps", force: :cascade do |t|
    t.string "app_id", null: false
    t.string "name", null: false
    t.string "developer"
    t.string "bundle_id"
    t.decimal "price"
    t.string "currency"
    t.float "average_rating"
    t.integer "rating_count"
    t.string "version"
    t.text "description"
    t.string "icon_url"
    t.string "keyword"
    t.integer "search_rank"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "keyword"], name: "index_apps_on_app_id_and_keyword", unique: true
    t.index ["app_id"], name: "index_apps_on_app_id"
    t.index ["keyword"], name: "index_apps_on_keyword"
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "app_id", null: false
    t.string "review_id", null: false
    t.string "author"
    t.string "title"
    t.text "content"
    t.integer "rating"
    t.string "version"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_reviews_on_app_id"
    t.index ["published_at"], name: "index_reviews_on_published_at"
    t.index ["rating"], name: "index_reviews_on_rating"
    t.index ["review_id"], name: "index_reviews_on_review_id", unique: true
  end

  add_foreign_key "reviews", "apps"
end
