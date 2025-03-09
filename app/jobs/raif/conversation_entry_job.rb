# frozen_string_literal: true

module Raif
  class ConversationEntryJob < ApplicationJob

    before_enqueue do |job|
      conversation_entry = job.arguments.first[:conversation_entry]
      conversation_entry.update_columns(started_at: Time.current)
    end

    def perform(conversation_entry:)
      conversation_entry.process_entry!
      conversation_entry.broadcast_replace_to conversation

      Turbo::StreamsChannel.broadcast_action_to(
        conversation,
        action: :raif_scroll_to_bottom,
        target: dom_id(conversation, :entries)
      )
    rescue StandardError
      conversation_entry.failed!
      conversation_entry.broadcast_replace_to conversation
    end

  end
end
