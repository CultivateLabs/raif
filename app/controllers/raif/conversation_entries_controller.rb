# frozen_string_literal: true

class Raif::ConversationEntriesController < Raif::ApplicationController
  before_action :set_conversation

  def new
    @conversation_entry = @conversation.entries.new

    @form_partial = if params[:user_tool_type]
      @conversation_entry.raif_user_tool_invocation = user_tool_type.new
      "raif/conversation_entries/form_with_user_tool_invocation"
    else
      "raif/conversation_entries/form_with_available_tools"
    end
  end

  def create
    user_tool_invocation = if params[:user_tool_type].present?
      user_tool_params = params[:conversation_entry].delete(:raif_user_tool_invocation_attributes)
      user_tool_type.new(user_tool_params.permit(user_tool_type.tool_params))
    end

    @conversation_entry = @conversation.entries.new(conversation_entry_params)
    @conversation_entry.raif_user_tool_invocation = user_tool_invocation
    @conversation_entry.creator = current_user

    if @conversation_entry.save
      Raif::ConversationEntryJob.perform_later(conversation_entry: @conversation_entry)
    end
  end

private

  def set_conversation
    @conversation = Raif::Conversation.find(params[:conversation_id])
  end

  def conversation_entry_params
    params.require(:conversation_entry).permit(:user_message)
  end

  def user_tool_type
    @user_tool_type ||= begin
      unless Raif.config.user_tool_types.include?(params[:user_tool_type])
        raise Raif::Errors::InvalidUserToolTypeError,
          "Invalid Raif user tool type - not in Raif.config.user_tool_types: #{params[:user_tool_type]}"
      end

      user_tool_type = params[:user_tool_type].constantize

      unless user_tool_type.ancestors.include?(Raif::UserToolInvocation)
        raise Raif::Errors::InvalidUserToolTypeError,
          "Invalid Raif user tool type - not a descendant of Raif::UserToolInvocation: #{params[:user_tool_type]}"
      end

      user_tool_type
    end
  end

end
