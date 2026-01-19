# frozen_string_literal: true

class AddStartedAtToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :started_at, :datetime
    add_index :raif_model_completions, :started_at
  end
end
