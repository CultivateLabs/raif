# frozen_string_literal: true

class AddGeneratingEntryResponseToRaifConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_conversations, :generating_entry_response, :boolean, default: false, null: false
  end
end
