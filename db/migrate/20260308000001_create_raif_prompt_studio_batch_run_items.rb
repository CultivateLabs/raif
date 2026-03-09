# frozen_string_literal: true

class CreateRaifPromptStudioBatchRunItems < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    create_table :raif_prompt_studio_batch_run_items do |t|
      t.references :batch_run, null: false, foreign_key: { to_table: :raif_prompt_studio_batch_runs }
      t.bigint :source_task_id, null: false
      t.bigint :result_task_id
      t.bigint :judge_task_id
      t.string :status, default: "pending", null: false
      t.column :metadata, json_column_type

      t.timestamps
    end

    add_foreign_key :raif_prompt_studio_batch_run_items, :raif_tasks, column: :source_task_id
    add_foreign_key :raif_prompt_studio_batch_run_items, :raif_tasks, column: :result_task_id
    add_foreign_key :raif_prompt_studio_batch_run_items, :raif_tasks, column: :judge_task_id
    add_index :raif_prompt_studio_batch_run_items, :status
  end
end
