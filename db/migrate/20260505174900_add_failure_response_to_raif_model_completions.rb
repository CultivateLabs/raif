# frozen_string_literal: true

class AddFailureResponseToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :failure_response_status, :integer
    add_column :raif_model_completions, :failure_response_body, :text
  end
end
