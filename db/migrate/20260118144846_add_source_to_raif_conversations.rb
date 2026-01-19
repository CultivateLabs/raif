# frozen_string_literal: true

class AddSourceToRaifConversations < ActiveRecord::Migration[7.1]
  def change
    add_reference :raif_conversations, :source, polymorphic: true, index: true
  end
end
