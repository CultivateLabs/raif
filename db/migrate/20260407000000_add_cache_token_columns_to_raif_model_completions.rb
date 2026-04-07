# frozen_string_literal: true

class AddCacheTokenColumnsToRaifModelCompletions < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_model_completions, :cache_read_input_tokens, :integer
    add_column :raif_model_completions, :cache_creation_input_tokens, :integer
  end
end
