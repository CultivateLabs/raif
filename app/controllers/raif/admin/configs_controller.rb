# frozen_string_literal: true

module Raif
  module Admin
    class ConfigsController < Raif::Admin::ApplicationController

      def show
        @config = Raif.config
        @config_settings = build_config_settings
      end

    private

      def build_config_settings
        [
          { key: "agent_types", value: format_array(@config.agent_types.to_a) },
          { key: "anthropic_api_key", value: mask_sensitive_value(@config.anthropic_api_key) },
          { key: "anthropic_models_enabled", value: @config.anthropic_models_enabled },
          { key: "authorize_admin_controller_action", value: format_proc(@config.authorize_admin_controller_action) },
          { key: "authorize_controller_action", value: format_proc(@config.authorize_controller_action) },
          { key: "aws_bedrock_model_name_prefix", value: @config.aws_bedrock_model_name_prefix },
          { key: "aws_bedrock_region", value: @config.aws_bedrock_region },
          { key: "bedrock_embedding_models_enabled", value: @config.bedrock_embedding_models_enabled },
          { key: "bedrock_models_enabled", value: @config.bedrock_models_enabled },
          { key: "conversation_entries_controller", value: @config.conversation_entries_controller },
          { key: "conversation_llm_messages_max_length_default", value: @config.conversation_llm_messages_max_length_default },
          { key: "conversation_system_prompt_intro", value: truncate_text(@config.conversation_system_prompt_intro, 100) },
          { key: "conversation_types", value: format_array(@config.conversation_types.to_a) },
          { key: "conversations_controller", value: @config.conversations_controller },
          { key: "current_user_method", value: @config.current_user_method },
          { key: "default_embedding_model_key", value: @config.default_embedding_model_key },
          { key: "default_llm_model_key", value: @config.default_llm_model_key },
          { key: "evals_default_llm_judge_model_key", value: @config.evals_default_llm_judge_model_key },
          { key: "evals_verbose_output", value: @config.evals_verbose_output },
          { key: "google_api_key", value: mask_sensitive_value(@config.google_api_key) },
          { key: "google_models_enabled", value: @config.google_models_enabled },
          { key: "llm_api_requests_enabled", value: @config.llm_api_requests_enabled },
          { key: "llm_request_max_retries", value: @config.llm_request_max_retries },
          { key: "llm_request_retriable_exceptions", value: @config.llm_request_retriable_exceptions.map(&:name).join(", ") },
          { key: "model_superclass", value: @config.model_superclass },
          { key: "open_ai_api_key", value: mask_sensitive_value(@config.open_ai_api_key) },
          { key: "open_ai_api_version", value: @config.open_ai_api_version },
          { key: "open_ai_auth_header_style", value: @config.open_ai_auth_header_style },
          { key: "open_ai_base_url", value: @config.open_ai_base_url },
          { key: "open_ai_embedding_models_enabled", value: @config.open_ai_embedding_models_enabled },
          { key: "open_ai_models_enabled", value: @config.open_ai_models_enabled },
          { key: "open_router_api_key", value: mask_sensitive_value(@config.open_router_api_key) },
          { key: "open_router_app_name", value: @config.open_router_app_name },
          { key: "open_router_models_enabled", value: @config.open_router_models_enabled },
          { key: "open_router_site_url", value: @config.open_router_site_url },
          { key: "request_open_timeout", value: @config.request_open_timeout },
          { key: "request_read_timeout", value: @config.request_read_timeout },
          { key: "request_write_timeout", value: @config.request_write_timeout },
          { key: "streaming_update_chunk_size_threshold", value: @config.streaming_update_chunk_size_threshold },
          { key: "task_creator_optional", value: @config.task_creator_optional },
          { key: "task_system_prompt_intro", value: truncate_text(@config.task_system_prompt_intro, 100) },
          { key: "user_tool_types", value: format_array(@config.user_tool_types) }
        ]
      end

      def mask_sensitive_value(value)
        return "Not set" if value.blank?
        return "Not set" if value.include?("placeholder")

        "#{value[0...5]}#{"*" * 20}"
      end

      def format_proc(value)
        return "Not set" unless value.respond_to?(:call)

        source = value.source_location
        if source
          "Lambda/Proc defined at #{source[0]}:#{source[1]}"
        else
          "Lambda/Proc (source unavailable)"
        end
      end

      def truncate_text(text, length)
        return "Not set" if text.blank?
        return format_proc(text) if text.respond_to?(:call)

        text.length > length ? "#{text[0...length]}..." : text
      end

      def format_array(array)
        return "None" if array.blank?

        array.join(", ")
      end
    end
  end
end
