# frozen_string_literal: true

class AddSubjectAndConfigToRaifConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :raif_conversations, :subject, polymorphic: true, index: true
    add_column :raif_conversations, :config, :jsonb, null: false, default: {}
  end
end
