# frozen_string_literal: true

class CreateRaifPromptStudioBatchRuns < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    create_table :raif_prompt_studio_batch_runs do |t|
      t.string :task_type, null: false
      t.string :llm_model_key, null: false
      t.string :judge_type
      t.string :judge_llm_model_key
      t.send json_column_type, :judge_config, null: false
      t.integer :total_count, default: 0
      t.integer :completed_count, default: 0
      t.integer :failed_count, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at

      t.timestamps
    end
  end
end
