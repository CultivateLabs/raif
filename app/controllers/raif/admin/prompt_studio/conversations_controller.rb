# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class ConversationsController < BaseController
        def index
          @conversation_types = Raif::Conversation.distinct.pluck(:type).sort
          @selected_type = params[:conversation_type] if params[:conversation_type].present?

          if @selected_type.present?
            conversations = Raif::Conversation.where(type: @selected_type).order(created_at: :desc)
            @pagy, @conversations = pagy(conversations)
          end
        end

        def show
          @conversation = Raif::Conversation.find(params[:id])
          @comparison = build_prompt_comparison(@conversation)
        end
      end
    end
  end
end
