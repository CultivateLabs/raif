# frozen_string_literal: true

module Raif
  class ConversationEntryJob < ApplicationJob

    before_enqueue do |job|
      conversation_entry = job.arguments.first[:conversation_entry]
      conversation_entry.update_columns(started_at: Time.current)

      unless conversation_entry.raif_conversation.generating_entry_response?
        conversation_entry.raif_conversation.update_columns(generating_entry_response: true)
      end
    end

    def perform(conversation_entry:)
      conversation = conversation_entry.raif_conversation
      conversation_entry.process_entry!

      Turbo::StreamsChannel.broadcast_render_to conversation,
        partial: "raif/conversations/entry_processed",
        locals: { conversation: conversation, conversation_entry: conversation_entry }
    rescue StandardError => e
      logger.error "Error processing conversation entry: #{e.message}"
      logger.error e.backtrace.join("\n")

      conversation_entry.raif_conversation.update_columns(generating_entry_response: false)
      conversation_entry.failed!
      conversation_entry.broadcast_replace_to conversation
    end

  end
end
