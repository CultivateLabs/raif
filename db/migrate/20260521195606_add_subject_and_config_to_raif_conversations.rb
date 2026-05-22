# frozen_string_literal: true

class AddSubjectAndConfigToRaifConversations < ActiveRecord::Migration[7.1]
  def change
    json_column_type = if connection.adapter_name.downcase.include?("postgresql")
      :jsonb
    else
      :json
    end

    add_reference :raif_conversations, :subject, polymorphic: true, index: true
    add_column :raif_conversations, :config, json_column_type, null: false
  end
end
