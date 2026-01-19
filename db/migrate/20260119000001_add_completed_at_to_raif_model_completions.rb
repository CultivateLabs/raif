# frozen_string_literal: true

class AddCompletedAtToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :completed_at, :datetime
    add_index :raif_model_completions, :completed_at
  end
end
