# frozen_string_literal: true

class AddExecutionContextToRaifConversationEntries < ActiveRecord::Migration[7.1]
  def change
    column_type = connection.adapter_name.downcase.include?("postgresql") ? :jsonb : :json
    add_column :raif_conversation_entries, :execution_context, column_type
  end
end
