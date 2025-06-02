# frozen_string_literal: true

module Raif
  class Configuration
    attr_accessor :agent_types,
      :anthropic_api_key,
      :bedrock_models_enabled,
      :anthropic_models_enabled,
      :authorize_admin_controller_action,
      :authorize_controller_action,
      :aws_bedrock_model_name_prefix,
      :aws_bedrock_region,
      :bedrock_embedding_models_enabled,
      :conversation_entries_controller,
      :conversation_system_prompt_intro,
      :conversation_types,
      :conversations_controller,
      :current_user_method,
      :default_embedding_model_key,
      :default_llm_model_key,
      :llm_api_requests_enabled,
      :llm_request_max_retries,
      :llm_request_retriable_exceptions,
      :model_superclass,
      :open_ai_api_key,
      :open_ai_embedding_models_enabled,
      :open_ai_models_enabled,
      :open_router_api_key,
      :open_router_models_enabled,
      :open_router_app_name,
      :open_router_site_url,
      :task_system_prompt_intro,
      :user_tool_types

    alias_method :anthropic_bedrock_models_enabled, :bedrock_models_enabled
    alias_method :anthropic_bedrock_models_enabled=, :bedrock_models_enabled=

    alias_method :aws_bedrock_titan_embedding_models_enabled, :bedrock_embedding_models_enabled
    alias_method :aws_bedrock_titan_embedding_models_enabled=, :bedrock_embedding_models_enabled=

    def initialize
      # Set default config
      @agent_types = Set.new(["Raif::Agents::ReActAgent", "Raif::Agents::NativeToolCallingAgent"])
      @anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
      @bedrock_models_enabled = false
      @anthropic_models_enabled = ENV["ANTHROPIC_API_KEY"].present?
      @authorize_admin_controller_action = ->{ false }
      @authorize_controller_action = ->{ false }
      @aws_bedrock_region = "us-east-1"
      @aws_bedrock_model_name_prefix = "us"
      @bedrock_embedding_models_enabled = false
      @task_system_prompt_intro = "You are a helpful assistant."
      @conversation_entries_controller = "Raif::ConversationEntriesController"
      @conversation_system_prompt_intro = "You are a helpful assistant who is collaborating with a teammate."
      @conversation_types = Set.new(["Raif::Conversation"])
      @conversations_controller = "Raif::ConversationsController"
      @current_user_method = :current_user
      @default_embedding_model_key = "open_ai_text_embedding_3_small"
      @default_llm_model_key = "open_ai_gpt_4o"
      @llm_api_requests_enabled = true
      @llm_request_max_retries = 2
      @llm_request_retriable_exceptions = [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Faraday::ServerError,
      ]
      @model_superclass = "ApplicationRecord"
      @open_ai_api_key = ENV["OPENAI_API_KEY"]
      @open_ai_embedding_models_enabled = ENV["OPENAI_API_KEY"].present?
      @open_ai_models_enabled = ENV["OPENAI_API_KEY"].present?
      @open_router_api_key = ENV["OPENROUTER_API_KEY"]
      @open_router_models_enabled = ENV["OPENROUTER_API_KEY"].present?
      @open_router_app_name = nil
      @open_router_site_url = nil
      @user_tool_types = []
    end

    def validate!
      if Raif.llm_registry.blank?
        puts <<~EOS

          !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
          No LLMs are enabled in Raif. Make sure you have an API key configured for at least one LLM provider. You can do this by setting an API key in your environment variables or in config/initializers/raif.rb (e.g. ENV["OPENAI_API_KEY"], ENV["ANTHROPIC_API_KEY"], ENV["OPENROUTER_API_KEY"]).

          See the README for more information: https://github.com/CultivateLabs/raif#setup
          !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        EOS

        return
      end

      unless Raif.available_llm_keys.include?(default_llm_model_key.to_sym)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.default_llm_model_key was set to #{default_llm_model_key}, but must be one of: #{Raif.available_llm_keys.join(", ")}"
      end

      if Raif.embedding_model_registry.present? && !Raif.available_embedding_model_keys.include?(default_embedding_model_key.to_sym)
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.default_embedding_model_key was set to #{default_embedding_model_key}, but must be one of: #{Raif.available_embedding_model_keys.join(", ")}" # rubocop:disable Layout/LineLength
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

      if open_ai_models_enabled && open_ai_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_api_key is required when Raif.config.open_ai_models_enabled is true. Set it via Raif.config.open_ai_api_key or ENV[\"OPENAI_API_KEY\"]" # rubocop:disable Layout/LineLength
      end

      if open_ai_embedding_models_enabled && open_ai_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_ai_api_key is required when Raif.config.open_ai_embedding_models_enabled is true. Set it via Raif.config.open_ai_api_key or ENV[\"OPENAI_API_KEY\"]" # rubocop:disable Layout/LineLength
      end

      if anthropic_models_enabled && anthropic_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.anthropic_api_key is required when Raif.config.anthropic_models_enabled is true. Set it via Raif.config.anthropic_api_key or ENV['ANTHROPIC_API_KEY']" # rubocop:disable Layout/LineLength
      end

      if open_router_models_enabled && open_router_api_key.blank?
        raise Raif::Errors::InvalidConfigError,
          "Raif.config.open_router_api_key is required when Raif.config.open_router_models_enabled is true. Set it via Raif.config.open_router_api_key or ENV['OPENROUTER_API_KEY']" # rubocop:disable Layout/LineLength
      end
    end

  end
end
