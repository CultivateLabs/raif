# frozen_string_literal: true

class AddToolChoiceToRaifModelCompletions < ActiveRecord::Migration[7.2]
  def change
    add_column :raif_model_completions, :tool_choice, :string
  end
end
