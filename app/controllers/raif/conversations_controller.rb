# frozen_string_literal: true

class Raif::ConversationsController < Raif::ApplicationController
  before_action :validate_conversation_type, unless: ->{ params[:action] == "index" && params[:conversation_type].blank? }

  def index
    @conversations = conversations_scope
  end

  def show
    @conversations = conversations_scope

    @conversation = if params[:id] == "latest"
      if @conversations.any?
        @conversations.first
      else
        conversation = build_new_conversation
        conversation.save!
        conversation
      end
    else
      @conversations.find(params[:id])
    end
  end

private

  def build_new_conversation
    raif_conversation_type.new(creator: raif_current_user)
  end

  def conversations_scope
    if params[:conversation_type].present?
      raif_conversation_type
    else
      Raif::Conversation
    end.newest_first.where(creator: raif_current_user)
  end

  def conversation_type_param
    params[:conversation_type].presence || "Raif::Conversation"
  end

  def validate_conversation_type
    unless Raif.config.conversation_types.include?(conversation_type_param)
      logger.error("Invalid Raif conversation type - not in Raif.config.conversation_types: #{conversation_type_param}")
      logger.debug("\n\n\e[33m!!! Make sure to add the conversation type in Raif.config.conversation_types\e[0m\n")
      head :bad_request
    end
  end

  def raif_conversation_type
    @raif_conversation_type ||= begin
      unless Raif.config.conversation_types.include?(conversation_type_param)
        raise Raif::Errors::InvalidConversationTypeError,
          "Invalid Raif conversation type - not in Raif.config.conversation_types: #{conversation_type_param}"
      end

      conversation_type = conversation_type_param.constantize

      unless conversation_type == Raif::Conversation || conversation_type.ancestors.include?(Raif::Conversation)
        raise Raif::Errors::InvalidConversationTypeError,
          "Invalid Raif conversation type - not a descendant of Raif::Conversation: #{conversation_type_param}"
      end

      conversation_type
    end
  end

end
