# frozen_string_literal: true

class AddResponseFinishReasonToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :response_finish_reason, :string
  end
end
