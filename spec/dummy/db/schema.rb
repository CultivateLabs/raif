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

ActiveRecord::Schema[8.0].define(version: 2025_05_27_213016) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "raif_agents", force: :cascade do |t|
    t.string "type", null: false
    t.string "llm_model_key", null: false
    t.text "task"
    t.text "system_prompt"
    t.text "final_answer"
    t.integer "max_iterations", default: 10, null: false
    t.integer "iteration_count", default: 0, null: false
    t.jsonb "available_model_tools", null: false
    t.string "creator_type", null: false
    t.bigint "creator_id", null: false
    t.string "requested_language_key"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.text "failure_reason"
    t.jsonb "conversation_history", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_raif_agents_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_agents_on_creator"
  end

  create_table "raif_conversation_entries", force: :cascade do |t|
    t.bigint "raif_conversation_id", null: false
    t.string "creator_type", null: false
    t.bigint "creator_id", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.text "user_message"
    t.text "raw_response"
    t.text "model_response_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_raif_conversation_entries_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_conversation_entries_on_creator"
    t.index ["raif_conversation_id"], name: "index_raif_conversation_entries_on_raif_conversation_id"
  end

  create_table "raif_conversations", force: :cascade do |t|
    t.string "llm_model_key", null: false
    t.string "creator_type", null: false
    t.bigint "creator_id", null: false
    t.string "requested_language_key"
    t.string "type", null: false
    t.text "system_prompt"
    t.jsonb "available_model_tools", null: false
    t.jsonb "available_user_tools", null: false
    t.integer "conversation_entries_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "response_format", default: 0, null: false
    t.index ["created_at"], name: "index_raif_conversations_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_conversations_on_creator"
  end

  create_table "raif_model_completions", force: :cascade do |t|
    t.string "source_type"
    t.bigint "source_id"
    t.string "llm_model_key", null: false
    t.string "model_api_name", null: false
    t.jsonb "available_model_tools", null: false
    t.jsonb "messages", null: false
    t.text "system_prompt"
    t.integer "response_format", default: 0, null: false
    t.string "response_format_parameter"
    t.decimal "temperature", precision: 5, scale: 3
    t.integer "max_completion_tokens"
    t.integer "completion_tokens"
    t.integer "prompt_tokens"
    t.text "raw_response"
    t.jsonb "response_tool_calls"
    t.integer "total_tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "prompt_token_cost", precision: 10, scale: 6
    t.decimal "output_token_cost", precision: 10, scale: 6
    t.decimal "total_cost", precision: 10, scale: 6
    t.integer "retry_count", default: 0, null: false
    t.string "response_id"
    t.jsonb "response_array"
    t.index ["created_at"], name: "index_raif_model_completions_on_created_at"
    t.index ["source_type", "source_id"], name: "index_raif_model_completions_on_source"
  end

  create_table "raif_model_tool_invocations", force: :cascade do |t|
    t.string "source_type", null: false
    t.bigint "source_id", null: false
    t.string "tool_type", null: false
    t.jsonb "tool_arguments", null: false
    t.jsonb "result", null: false
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_id"], name: "index_raif_model_tool_invocations_on_source"
  end

  create_table "raif_tasks", force: :cascade do |t|
    t.string "type", null: false
    t.text "prompt"
    t.text "raw_response"
    t.string "creator_type", null: false
    t.bigint "creator_id", null: false
    t.text "system_prompt"
    t.string "requested_language_key"
    t.integer "response_format", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.jsonb "available_model_tools", null: false
    t.string "llm_model_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_raif_tasks_on_completed_at"
    t.index ["created_at"], name: "index_raif_tasks_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_tasks_on_creator"
    t.index ["failed_at"], name: "index_raif_tasks_on_failed_at"
    t.index ["started_at"], name: "index_raif_tasks_on_started_at"
    t.index ["type", "completed_at"], name: "index_raif_tasks_on_type_and_completed_at"
    t.index ["type", "failed_at"], name: "index_raif_tasks_on_type_and_failed_at"
    t.index ["type", "started_at"], name: "index_raif_tasks_on_type_and_started_at"
    t.index ["type"], name: "index_raif_tasks_on_type"
  end

  create_table "raif_test_users", force: :cascade do |t|
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "raif_user_tool_invocations", force: :cascade do |t|
    t.bigint "raif_conversation_entry_id", null: false
    t.string "type", null: false
    t.jsonb "tool_settings", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["raif_conversation_entry_id"], name: "index_raif_user_tool_invocations_on_raif_conversation_entry_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "raif_conversation_entries", "raif_conversations"
  add_foreign_key "raif_user_tool_invocations", "raif_conversation_entries"
end
