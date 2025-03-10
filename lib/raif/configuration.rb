# frozen_string_literal: true

module Raif
  class Configuration
    attr_accessor :authorize_controller_action,
      :authorize_admin_controller_action,
      :aws_bedrock_region,
      :base_system_prompt,
      :conversation_entries_controller,
      :conversation_types,
      :conversations_controller,
      :current_user_method,
      :default_llm_model_name,
      :llm_api_requests_enabled,
      :model_superclass,
      :user_tool_types

    def initialize
      @aws_bedrock_region = "us-east-1"
      @authorize_controller_action = ->{ false }
      @authorize_admin_controller_action = ->{ false }
      @base_system_prompt = "You are a friendly assistant."
      @conversation_entries_controller = "Raif::ConversationEntriesController"
      @conversation_types = ["Raif::Conversation"]
      @conversations_controller = "Raif::ConversationsController"
      @current_user_method = :current_user
      @default_llm_model_name = "open_ai_gpt_4o"
      @llm_api_requests_enabled = true
      @model_superclass = "ApplicationRecord"
      @user_tool_types = []
    end

    def validate!
      unless Raif.llm_for_key(default_llm_model_name.to_sym).present?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.default_llm_model_name was set to #{default_llm_model_name}, but must be one of: #{Raif.available_llm_keys.join(", ")}"
      end

      if authorize_controller_action.respond_to?(:call)
        authorize_controller_action.freeze
      else
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.authorize_controller_action must respond to :call and return a boolean"
      end

      if authorize_admin_controller_action.respond_to?(:call)
        authorize_admin_controller_action.freeze
      else
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.authorize_admin_controller_action must respond to :call and return a boolean"
      end
    end

  end
end
