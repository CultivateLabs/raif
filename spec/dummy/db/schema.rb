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

ActiveRecord::Schema[8.1].define(version: 2026_01_19_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "raif_agents", force: :cascade do |t|
    t.jsonb "available_model_tools", null: false
    t.datetime "completed_at"
    t.jsonb "conversation_history", null: false
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.string "creator_type", null: false
    t.datetime "failed_at"
    t.text "failure_reason"
    t.text "final_answer"
    t.integer "iteration_count", default: 0, null: false
    t.string "llm_model_key", null: false
    t.integer "max_iterations", default: 10, null: false
    t.string "requested_language_key"
    t.jsonb "run_with"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "started_at"
    t.text "system_prompt"
    t.text "task"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_raif_agents_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_agents_on_creator"
    t.index ["source_type", "source_id"], name: "index_raif_agents_on_source"
  end

  create_table "raif_conversation_entries", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.string "creator_type", null: false
    t.datetime "failed_at"
    t.text "model_response_message"
    t.bigint "raif_conversation_id", null: false
    t.text "raw_response"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.text "user_message"
    t.index ["created_at"], name: "index_raif_conversation_entries_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_conversation_entries_on_creator"
    t.index ["raif_conversation_id"], name: "index_raif_conversation_entries_on_raif_conversation_id"
  end

  create_table "raif_conversations", force: :cascade do |t|
    t.jsonb "available_model_tools", null: false
    t.jsonb "available_user_tools", null: false
    t.integer "conversation_entries_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.string "creator_type", null: false
    t.boolean "generating_entry_response", default: false, null: false
    t.integer "llm_messages_max_length"
    t.string "llm_model_key", null: false
    t.string "requested_language_key"
    t.integer "response_format", default: 0, null: false
    t.bigint "source_id"
    t.string "source_type"
    t.text "system_prompt"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_raif_conversations_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_conversations_on_creator"
    t.index ["source_type", "source_id"], name: "index_raif_conversations_on_source"
  end

  create_table "raif_model_completions", force: :cascade do |t|
    t.jsonb "available_model_tools", null: false
    t.jsonb "citations"
    t.datetime "completed_at"
    t.integer "completion_tokens"
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.string "failure_error"
    t.string "failure_reason"
    t.string "llm_model_key", null: false
    t.integer "max_completion_tokens"
    t.jsonb "messages", null: false
    t.string "model_api_name", null: false
    t.decimal "output_token_cost", precision: 10, scale: 6
    t.decimal "prompt_token_cost", precision: 10, scale: 6
    t.integer "prompt_tokens"
    t.text "raw_response"
    t.jsonb "response_array"
    t.integer "response_format", default: 0, null: false
    t.string "response_format_parameter"
    t.string "response_id"
    t.jsonb "response_tool_calls"
    t.integer "retry_count", default: 0, null: false
    t.bigint "source_id"
    t.string "source_type"
    t.boolean "stream_response", default: false, null: false
    t.text "system_prompt"
    t.decimal "temperature", precision: 5, scale: 3
    t.string "tool_choice"
    t.decimal "total_cost", precision: 10, scale: 6
    t.integer "total_tokens"
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_raif_model_completions_on_completed_at"
    t.index ["created_at"], name: "index_raif_model_completions_on_created_at"
    t.index ["failed_at"], name: "index_raif_model_completions_on_failed_at"
    t.index ["source_type", "source_id"], name: "index_raif_model_completions_on_source"
  end

  create_table "raif_model_tool_invocations", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.string "provider_tool_call_id"
    t.jsonb "result", null: false
    t.bigint "source_id", null: false
    t.string "source_type", null: false
    t.jsonb "tool_arguments", null: false
    t.string "tool_type", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_id"], name: "index_raif_model_tool_invocations_on_source"
  end

  create_table "raif_tasks", force: :cascade do |t|
    t.jsonb "available_model_tools", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "creator_type"
    t.datetime "failed_at"
    t.string "llm_model_key", null: false
    t.text "prompt"
    t.text "raw_response"
    t.string "requested_language_key"
    t.integer "response_format", default: 0, null: false
    t.jsonb "run_with"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "started_at"
    t.text "system_prompt"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_raif_tasks_on_completed_at"
    t.index ["created_at"], name: "index_raif_tasks_on_created_at"
    t.index ["creator_type", "creator_id"], name: "index_raif_tasks_on_creator"
    t.index ["failed_at"], name: "index_raif_tasks_on_failed_at"
    t.index ["source_type", "source_id"], name: "index_raif_tasks_on_source"
    t.index ["started_at"], name: "index_raif_tasks_on_started_at"
    t.index ["type", "completed_at"], name: "index_raif_tasks_on_type_and_completed_at"
    t.index ["type", "failed_at"], name: "index_raif_tasks_on_type_and_failed_at"
    t.index ["type", "started_at"], name: "index_raif_tasks_on_type_and_started_at"
    t.index ["type"], name: "index_raif_tasks_on_type"
  end

  create_table "raif_test_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "updated_at", null: false
  end

  create_table "raif_user_tool_invocations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "raif_conversation_entry_id", null: false
    t.jsonb "tool_settings", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["raif_conversation_entry_id"], name: "index_raif_user_tool_invocations_on_raif_conversation_entry_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "raif_conversation_entries", "raif_conversations"
  add_foreign_key "raif_user_tool_invocations", "raif_conversation_entries"
end
