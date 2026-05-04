# frozen_string_literal: true

class CreateRaifModelCompletionBatches < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    create_table :raif_model_completion_batches do |t|
      t.string :type, null: false
      t.references :creator, polymorphic: true, index: true
      t.string :llm_model_key, null: false
      t.string :model_api_name, null: false
      t.string :provider_batch_id
      t.string :status, default: "pending", null: false
      t.string :completion_handler_class_name
      t.datetime :submitted_at
      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :failed_at
      t.datetime :next_poll_at
      t.send json_column_type, :request_counts
      t.send json_column_type, :provider_response
      t.send json_column_type, :metadata
      t.string :failure_error
      t.text :failure_reason
      t.decimal :prompt_token_cost, precision: 10, scale: 6
      t.decimal :output_token_cost, precision: 10, scale: 6
      t.decimal :total_cost, precision: 10, scale: 6

      t.timestamps
    end

    add_index :raif_model_completion_batches, :type
    add_index :raif_model_completion_batches, :provider_batch_id
    add_index :raif_model_completion_batches, :status
    add_index :raif_model_completion_batches, :submitted_at
    add_index :raif_model_completion_batches, :next_poll_at
  end
end
