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
      t.references :source_task, null: false, foreign_key: { to_table: :raif_tasks }
      t.references :result_task, foreign_key: { to_table: :raif_tasks }
      t.references :judge_task, foreign_key: { to_table: :raif_tasks }
      t.string :status, default: "pending", null: false
      t.column :metadata, json_column_type

      t.timestamps
    end

    add_index :raif_prompt_studio_batch_run_items, :status
  end
end
