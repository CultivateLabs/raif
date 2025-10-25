# frozen_string_literal: true

class AddLlmMessagesMaxLengthToRaifConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_conversations, :llm_messages_max_length, :integer

    reversible do |dir|
      dir.up do
        # Set default value for existing conversations
        execute "UPDATE raif_conversations SET llm_messages_max_length = 50 WHERE llm_messages_max_length IS NULL"
      end
    end
  end
end
