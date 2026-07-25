# frozen_string_literal: true

class AddDenormalizedCompletionFieldsToRaifConversationEntries < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    # Copied from the entry's winning model completion at finalization so
    # historical conversations keep their citations and model key after old
    # completion rows are culled.
    add_column :raif_conversation_entries, :citations, json_column_type
    add_column :raif_conversation_entries, :llm_model_key, :string
  end
end
