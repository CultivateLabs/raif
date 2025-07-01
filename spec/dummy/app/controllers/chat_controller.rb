# frozen_string_literal: true

class ChatController < ApplicationController
  def index
    conversation_type = params[:conversation_type] == "html" ? Raif::Conversations::HtmlConversationWithTools : Raif::Conversation
    # Find the latest conversation for this user or create a new one
    @conversation = conversation_type.where(creator: current_user).newest_first.first

    if @conversation.nil?
      @conversation = conversation_type.new(creator: current_user)
      @conversation.save!
    end
  end
end
