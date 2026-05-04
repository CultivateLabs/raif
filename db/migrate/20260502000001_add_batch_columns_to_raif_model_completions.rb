# frozen_string_literal: true

class AddBatchColumnsToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_reference :raif_model_completions,
      :raif_model_completion_batch,
      foreign_key: { to_table: :raif_model_completion_batches },
      index: true
    add_column :raif_model_completions, :batch_custom_id, :string
    add_index :raif_model_completions, :batch_custom_id
  end
end
