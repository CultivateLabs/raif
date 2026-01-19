# frozen_string_literal: true

class AddFailureTrackingToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :failed_at, :datetime
    add_column :raif_model_completions, :failure_error, :string
    add_column :raif_model_completions, :failure_reason, :text
    add_index :raif_model_completions, :failed_at
  end
end
