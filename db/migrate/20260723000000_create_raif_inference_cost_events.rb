# frozen_string_literal: true

class CreateRaifInferenceCostEvents < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    create_table :raif_inference_cost_events do |t|
      # Live link to the completion. DB-level ON DELETE SET NULL means host
      # culls can use delete_all with zero coordination; presence of this FK
      # means the completion row still exists.
      t.references :raif_model_completion,
        null: true,
        foreign_key: { to_table: :raif_model_completions, on_delete: :nullify },
        index: { unique: true }
      # Retained forever (plain bigint, no FK). After the completion is culled,
      # this id locates the archived record inside an archive payload.
      t.bigint :original_model_completion_id, null: false

      # Copied polymorphic source; no FK because the source may be culled later.
      t.string :source_type
      t.bigint :source_id
      # Concrete STI class of the source (e.g. "Raif::Tasks::Foo"); admin stats
      # group by this.
      t.string :source_class_name

      t.string :llm_model_key, null: false
      t.string :model_api_name, null: false

      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.integer :cache_read_input_tokens
      t.integer :cache_creation_input_tokens

      t.decimal :prompt_token_cost, precision: 10, scale: 6
      t.decimal :output_token_cost, precision: 10, scale: 6
      t.decimal :total_cost, precision: 10, scale: 6

      t.integer :retry_count, default: 0, null: false
      # Plain column, no FK: batches may be culled later.
      t.bigint :raif_model_completion_batch_id

      # Mirror of the completion's created_at; the time axis for windowed cost queries.
      t.datetime :incurred_at, null: false
      t.datetime :completion_completed_at
      t.datetime :completion_failed_at

      # Host-populated context via Raif.config.inference_cost_event_metadata.
      t.send json_column_type, :metadata

      t.timestamps
    end

    add_index :raif_inference_cost_events,
      :original_model_completion_id,
      name: "index_raif_inference_cost_events_on_original_completion_id"
    add_index :raif_inference_cost_events, [:source_type, :source_id]
    add_index :raif_inference_cost_events, :incurred_at
    add_index :raif_inference_cost_events,
      [:source_type, :incurred_at],
      name: "index_raif_inference_cost_events_on_source_type_incurred_at"
  end
end
