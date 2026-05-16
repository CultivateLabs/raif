# frozen_string_literal: true

class AddUniqueIndexOnRaifModelCompletionBatchCustomIds < ActiveRecord::Migration[7.1]
  # Within a single batch, batch_custom_id must be unique. Without this,
  # apply_batch_jsonl's `index_by(&:batch_custom_id)` would silently shadow
  # an earlier child completion when a producer accidentally generates a
  # duplicate identifier; the shadowed child would never receive its result.
  #
  # Partial: non-batch model completions have raif_model_completion_batch_id
  # IS NULL and don't participate in this constraint.
  def change
    add_index :raif_model_completions,
      [:raif_model_completion_batch_id, :batch_custom_id],
      unique: true,
      where: "raif_model_completion_batch_id IS NOT NULL",
      name: "index_raif_model_completions_on_batch_id_and_custom_id"
  end
end
