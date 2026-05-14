# frozen_string_literal: true

class AddLatestEntryAtToRaifConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :raif_conversations, :latest_entry_at, :datetime
  end
end
