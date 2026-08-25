# frozen_string_literal: true

# GENERATED FILE - DO NOT EDIT.
# Source of truth: model_manifest/*.rb
# Regenerate with: bin/generate_llm_registry

module Raif
  def self.default_llms
    {
      Raif::Llms::OpenAiCompletions => [
        {
          key: :open_ai_gpt_5_6_sol,
          api_name: "gpt-5.6-sol",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 30.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_6_terra,
          api_name: "gpt-5.6-terra",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 12.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_6_luna,
          api_name: "gpt-5.6-luna",
          input_token_cost: 0.2 / 1_000_000,
          output_token_cost: 1.2 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_5,
          api_name: "gpt-5.5",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 30.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_4,
          api_name: "gpt-5.4",
          input_token_cost: 2.5 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_2,
          api_name: "gpt-5.2",
          input_token_cost: 1.75 / 1_000_000,
          output_token_cost: 14.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_3,
          api_name: "gpt-5.3",
          input_token_cost: 1.75 / 1_000_000,
          output_token_cost: 14.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_1,
          api_name: "gpt-5.1",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5,
          api_name: "gpt-5",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_4_mini,
          api_name: "gpt-5.4-mini",
          input_token_cost: 0.75 / 1_000_000,
          output_token_cost: 4.5 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_4_nano,
          api_name: "gpt-5.4-nano",
          input_token_cost: 0.2 / 1_000_000,
          output_token_cost: 1.25 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_mini,
          api_name: "gpt-5-mini",
          input_token_cost: 0.25 / 1_000_000,
          output_token_cost: 2.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_5_nano,
          api_name: "gpt-5-nano",
          input_token_cost: 0.05 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_gpt_4o_mini,
          api_name: "gpt-4o-mini",
          input_token_cost: 0.15 / 1_000_000,
          output_token_cost: 0.6 / 1_000_000
        },
        {
          key: :open_ai_gpt_4o,
          api_name: "gpt-4o",
          input_token_cost: 2.5 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000
        },
        {
          key: :open_ai_gpt_3_5_turbo,
          api_name: "gpt-3.5-turbo",
          input_token_cost: 0.5 / 1_000_000,
          output_token_cost: 1.5 / 1_000_000,
          model_provider_settings: { supports_structured_outputs: false }
        },
        {
          key: :open_ai_gpt_4_1,
          api_name: "gpt-4.1",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 8.0 / 1_000_000
        },
        {
          key: :open_ai_gpt_4_1_mini,
          api_name: "gpt-4.1-mini",
          input_token_cost: 0.4 / 1_000_000,
          output_token_cost: 1.6 / 1_000_000
        },
        {
          key: :open_ai_gpt_4_1_nano,
          api_name: "gpt-4.1-nano",
          input_token_cost: 0.1 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000
        },
        {
          key: :open_ai_o1,
          api_name: "o1",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 60.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_o3,
          api_name: "o3",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 8.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_o3_mini,
          api_name: "o3-mini",
          input_token_cost: 1.1 / 1_000_000,
          output_token_cost: 4.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_o4_mini,
          api_name: "o4-mini",
          input_token_cost: 1.1 / 1_000_000,
          output_token_cost: 4.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        }
      ],
      Raif::Llms::OpenAiResponses => [
        {
          key: :open_ai_responses_gpt_5_6_sol,
          api_name: "gpt-5.6-sol",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 30.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_6_terra,
          api_name: "gpt-5.6-terra",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 12.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_6_luna,
          api_name: "gpt-5.6-luna",
          input_token_cost: 0.2 / 1_000_000,
          output_token_cost: 1.2 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_5,
          api_name: "gpt-5.5",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 30.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_4,
          api_name: "gpt-5.4",
          input_token_cost: 2.5 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_2,
          api_name: "gpt-5.2",
          input_token_cost: 1.75 / 1_000_000,
          output_token_cost: 14.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_3,
          api_name: "gpt-5.3",
          input_token_cost: 1.75 / 1_000_000,
          output_token_cost: 14.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_1,
          api_name: "gpt-5.1",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5,
          api_name: "gpt-5",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_4_mini,
          api_name: "gpt-5.4-mini",
          input_token_cost: 0.75 / 1_000_000,
          output_token_cost: 4.5 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_4_nano,
          api_name: "gpt-5.4-nano",
          input_token_cost: 0.2 / 1_000_000,
          output_token_cost: 1.25 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_mini,
          api_name: "gpt-5-mini",
          input_token_cost: 0.25 / 1_000_000,
          output_token_cost: 2.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_5_nano,
          api_name: "gpt-5-nano",
          input_token_cost: 0.05 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_4o_mini,
          api_name: "gpt-4o-mini",
          input_token_cost: 0.15 / 1_000_000,
          output_token_cost: 0.6 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_4o,
          api_name: "gpt-4o",
          input_token_cost: 2.5 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_3_5_turbo,
          api_name: "gpt-3.5-turbo",
          input_token_cost: 0.5 / 1_000_000,
          output_token_cost: 1.5 / 1_000_000,
          model_provider_settings: { supports_structured_outputs: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_4_1,
          api_name: "gpt-4.1",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 8.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_4_1_mini,
          api_name: "gpt-4.1-mini",
          input_token_cost: 0.4 / 1_000_000,
          output_token_cost: 1.6 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_gpt_4_1_nano,
          api_name: "gpt-4.1-nano",
          input_token_cost: 0.1 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_o1,
          api_name: "o1",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 60.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_o3,
          api_name: "o3",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 8.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_o3_mini,
          api_name: "o3-mini",
          input_token_cost: 1.1 / 1_000_000,
          output_token_cost: 4.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_o4_mini,
          api_name: "o4-mini",
          input_token_cost: 1.1 / 1_000_000,
          output_token_cost: 4.4 / 1_000_000,
          model_provider_settings: { supports_temperature: false },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution,
            Raif::ModelTools::ProviderManaged::ImageGeneration
          ]
        },
        {
          key: :open_ai_responses_o1_pro,
          api_name: "o1-pro",
          input_token_cost: 150.0 / 1_000_000,
          output_token_cost: 600.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_responses_o3_pro,
          api_name: "o3-pro",
          input_token_cost: 20.0 / 1_000_000,
          output_token_cost: 80.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_responses_gpt_5_pro,
          api_name: "gpt-5-pro",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 120.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_responses_gpt_5_2_pro,
          api_name: "gpt-5.2-pro",
          input_token_cost: 21.0 / 1_000_000,
          output_token_cost: 168.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_ai_responses_gpt_5_4_pro,
          api_name: "gpt-5.4-pro",
          input_token_cost: 30.0 / 1_000_000,
          output_token_cost: 180.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false, supports_structured_outputs: false }
        },
        {
          key: :open_ai_responses_gpt_5_5_pro,
          api_name: "gpt-5.5-pro",
          input_token_cost: 30.0 / 1_000_000,
          output_token_cost: 180.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        }
      ],
      Raif::Llms::Anthropic => [
        {
          key: :anthropic_claude_5_fable,
          api_name: "claude-fable-5",
          input_token_cost: 10.0 / 1_000_000,
          output_token_cost: 50.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_temperature: false, supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_8_opus,
          api_name: "claude-opus-4-8",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_temperature: false, supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_5_sonnet,
          api_name: "claude-sonnet-5",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_temperature: false, supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_7_opus,
          api_name: "claude-opus-4-7",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_temperature: false, supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_6_opus,
          api_name: "claude-opus-4-6",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_6_sonnet,
          api_name: "claude-sonnet-4-6",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_5_opus,
          api_name: "claude-opus-4-5",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_5_sonnet,
          api_name: "claude-sonnet-4-5",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_5_haiku,
          api_name: "claude-haiku-4-5",
          input_token_cost: 1.0 / 1_000_000,
          output_token_cost: 5.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true },
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_1_opus,
          api_name: "claude-opus-4-1",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 75.0 / 1_000_000,
          max_completion_tokens: 32_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        }
      ],
      Raif::Llms::Bedrock => [
        {
          key: :bedrock_claude_5_fable,
          api_name: "anthropic.claude-fable-5",
          input_token_cost: 10.0 / 1_000_000,
          output_token_cost: 50.0 / 1_000_000,
          max_completion_tokens: 128_000
        },
        {
          key: :bedrock_claude_4_8_opus,
          api_name: "anthropic.claude-opus-4-8",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000
        },
        {
          key: :bedrock_claude_5_sonnet,
          api_name: "anthropic.claude-sonnet-5",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 128_000
        },
        {
          key: :bedrock_claude_4_7_opus,
          api_name: "anthropic.claude-opus-4-7",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000
        },
        {
          key: :bedrock_claude_4_6_opus,
          api_name: "anthropic.claude-opus-4-6-v1",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 128_000,
          model_provider_settings: { supports_structured_outputs: true }
        },
        {
          key: :bedrock_claude_4_6_sonnet,
          api_name: "anthropic.claude-sonnet-4-6",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true }
        },
        {
          key: :bedrock_claude_4_5_opus,
          api_name: "anthropic.claude-opus-4-5-20251101-v1:0",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true }
        },
        {
          key: :bedrock_claude_4_5_sonnet,
          api_name: "anthropic.claude-sonnet-4-5-20250929-v1:0",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true }
        },
        {
          key: :bedrock_claude_4_5_haiku,
          api_name: "anthropic.claude-haiku-4-5-20251001-v1:0",
          input_token_cost: 1.0 / 1_000_000,
          output_token_cost: 5.0 / 1_000_000,
          max_completion_tokens: 64_000,
          model_provider_settings: { supports_structured_outputs: true }
        },
        {
          key: :bedrock_claude_4_1_opus,
          api_name: "anthropic.claude-opus-4-1-20250805-v1:0",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 75.0 / 1_000_000,
          max_completion_tokens: 32_000
        },
        {
          key: :bedrock_claude_4_sonnet,
          api_name: "anthropic.claude-sonnet-4-20250514-v1:0",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 64_000
        },
        {
          key: :bedrock_claude_3_7_sonnet,
          api_name: "anthropic.claude-3-7-sonnet-20250219-v1:0",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 8_192
        },
        {
          key: :bedrock_claude_3_5_sonnet,
          api_name: "anthropic.claude-3-5-sonnet-20241022-v2:0",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 8_192
        },
        {
          key: :bedrock_amazon_nova_micro,
          api_name: "amazon.nova-micro-v1:0",
          input_token_cost: 0.0115 / 1_000_000,
          output_token_cost: 0.184 / 1_000_000,
          max_completion_tokens: 4_096
        },
        {
          key: :bedrock_amazon_nova_lite,
          api_name: "amazon.nova-lite-v1:0",
          input_token_cost: 0.0195 / 1_000_000,
          output_token_cost: 0.312 / 1_000_000,
          max_completion_tokens: 4_096
        },
        {
          key: :bedrock_amazon_nova_pro,
          api_name: "amazon.nova-pro-v1:0",
          input_token_cost: 0.2625 / 1_000_000,
          output_token_cost: 4.2 / 1_000_000,
          max_completion_tokens: 4_096
        },
        {
          key: :bedrock_deepseek_v3_2,
          api_name: "deepseek.v3.2",
          input_token_cost: 0.62 / 1_000_000,
          output_token_cost: 1.85 / 1_000_000,
          max_completion_tokens: 32_768
        },
        {
          key: :bedrock_deepseek_r1,
          api_name: "deepseek.r1-v1:0",
          input_token_cost: 1.35 / 1_000_000,
          output_token_cost: 5.4 / 1_000_000,
          max_completion_tokens: 32_768
        },
        {
          key: :bedrock_gpt_oss_120b,
          api_name: "openai.gpt-oss-120b-1:0",
          input_token_cost: 0.15 / 1_000_000,
          output_token_cost: 0.6 / 1_000_000,
          max_completion_tokens: 32_768
        },
        {
          key: :bedrock_gpt_oss_20b,
          api_name: "openai.gpt-oss-20b-1:0",
          input_token_cost: 0.07 / 1_000_000,
          output_token_cost: 0.3 / 1_000_000,
          max_completion_tokens: 32_768
        }
      ],
      Raif::Llms::OpenRouter => [
        {
          key: :open_router_claude_5_fable,
          api_name: "anthropic/claude-fable-5",
          input_token_cost: 10.0 / 1_000_000,
          output_token_cost: 50.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_router_claude_4_8_opus,
          api_name: "anthropic/claude-opus-4.8",
          input_token_cost: 5.0 / 1_000_000,
          output_token_cost: 25.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_router_claude_5_sonnet,
          api_name: "anthropic/claude-sonnet-5",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          model_provider_settings: { supports_temperature: false }
        },
        {
          key: :open_router_deepseek_chat_v3,
          api_name: "deepseek/deepseek-chat-v3-0324",
          input_token_cost: 0.2 / 1_000_000,
          output_token_cost: 0.77 / 1_000_000
        },
        {
          key: :open_router_deepseek_v3_1,
          api_name: "deepseek/deepseek-chat-v3.1",
          input_token_cost: 0.25 / 1_000_000,
          output_token_cost: 1.0 / 1_000_000
        },
        {
          key: :open_router_deepseek_v3_2,
          api_name: "deepseek/deepseek-v3.2",
          input_token_cost: 0.26 / 1_000_000,
          output_token_cost: 0.38 / 1_000_000
        },
        {
          key: :open_router_gemini_2_5_flash,
          api_name: "google/gemini-2.5-flash",
          input_token_cost: 0.3 / 1_000_000,
          output_token_cost: 2.5 / 1_000_000
        },
        {
          key: :open_router_gemini_3_5_flash,
          api_name: "google/gemini-3.5-flash",
          input_token_cost: 1.5 / 1_000_000,
          output_token_cost: 9.0 / 1_000_000
        },
        {
          key: :open_router_gemini_2_5_pro,
          api_name: "google/gemini-2.5-pro",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000
        },
        {
          key: :open_router_gemini_3_1_pro_preview,
          api_name: "google/gemini-3.1-pro-preview",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 12.0 / 1_000_000
        },
        {
          key: :open_router_gemini_3_1_flash_lite_preview,
          api_name: "google/gemini-3.1-flash-lite-preview",
          input_token_cost: 0.25 / 1_000_000,
          output_token_cost: 1.5 / 1_000_000
        },
        {
          key: :open_router_kimi_k2_thinking,
          api_name: "moonshotai/kimi-k2-thinking",
          input_token_cost: 0.45 / 1_000_000,
          output_token_cost: 2.35 / 1_000_000
        },
        {
          key: :open_router_kimi_k2_5,
          api_name: "moonshotai/kimi-k2.5",
          input_token_cost: 0.45 / 1_000_000,
          output_token_cost: 2.2 / 1_000_000
        },
        {
          key: :open_router_llama_3_3_70b_instruct,
          api_name: "meta-llama/llama-3.3-70b-instruct",
          input_token_cost: 0.1 / 1_000_000,
          output_token_cost: 0.25 / 1_000_000
        },
        {
          key: :open_router_llama_3_1_8b_instruct,
          api_name: "meta-llama/llama-3.1-8b-instruct",
          input_token_cost: 0.02 / 1_000_000,
          output_token_cost: 0.03 / 1_000_000
        },
        {
          key: :open_router_llama_4_maverick,
          api_name: "meta-llama/llama-4-maverick",
          input_token_cost: 0.15 / 1_000_000,
          output_token_cost: 0.6 / 1_000_000
        },
        {
          key: :open_router_llama_4_scout,
          api_name: "meta-llama/llama-4-scout",
          input_token_cost: 0.08 / 1_000_000,
          output_token_cost: 0.3 / 1_000_000
        },
        {
          key: :open_router_minimax_m2,
          api_name: "minimax/minimax-m2",
          input_token_cost: 0.255 / 1_000_000,
          output_token_cost: 1.02 / 1_000_000
        },
        {
          key: :open_router_minimax_m2_1,
          api_name: "minimax/minimax-m2.1",
          input_token_cost: 0.27 / 1_000_000,
          output_token_cost: 0.95 / 1_000_000
        },
        {
          key: :open_router_minimax_m2_5,
          api_name: "minimax/minimax-m2.5",
          input_token_cost: 0.27 / 1_000_000,
          output_token_cost: 0.95 / 1_000_000
        },
        {
          key: :open_router_mistral_large_3_2512,
          api_name: "mistralai/mistral-large-2512",
          input_token_cost: 0.5 / 1_000_000,
          output_token_cost: 1.5 / 1_000_000
        },
        {
          key: :open_router_mistral_small_3_2_24b,
          api_name: "mistralai/mistral-small-3.2-24b-instruct",
          input_token_cost: 0.06 / 1_000_000,
          output_token_cost: 0.18 / 1_000_000
        },
        {
          key: :open_router_open_ai_gpt_oss_120b,
          api_name: "gpt-oss-120b",
          input_token_cost: 0.15 / 1_000_000,
          output_token_cost: 0.6 / 1_000_000
        },
        {
          key: :open_router_open_ai_gpt_oss_20b,
          api_name: "gpt-oss-20b",
          input_token_cost: 0.05 / 1_000_000,
          output_token_cost: 0.2 / 1_000_000
        },
        {
          key: :open_router_grok_4_20,
          api_name: "x-ai/grok-4.20",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 6.0 / 1_000_000
        },
        {
          key: :open_router_grok_4_5,
          api_name: "x-ai/grok-4.5",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 6.0 / 1_000_000
        },
        {
          key: :open_router_google_gemma_4_31b_it,
          api_name: "google/gemma-4-31b-it",
          input_token_cost: 0.14 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000
        }
      ],
      Raif::Llms::XAi => [
        {
          key: :x_ai_grok_4_5,
          api_name: "grok-4.5",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 6.0 / 1_000_000,
          model_provider_settings: { supports_batch_inference: false }
        },
        {
          key: :x_ai_grok_4_3,
          api_name: "grok-4.3",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 2.5 / 1_000_000
        },
        {
          key: :x_ai_grok_4_20_reasoning,
          api_name: "grok-4.20-0309-reasoning",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 2.5 / 1_000_000
        },
        {
          key: :x_ai_grok_4_20_non_reasoning,
          api_name: "grok-4.20-0309-non-reasoning",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 2.5 / 1_000_000
        }
      ],
      Raif::Llms::Google => [
        {
          key: :google_gemini_3_5_flash,
          api_name: "gemini-3.5-flash",
          input_token_cost: 1.5 / 1_000_000,
          output_token_cost: 9.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :google_gemini_3_1_pro,
          api_name: "gemini-3.1-pro-preview",
          input_token_cost: 2.0 / 1_000_000,
          output_token_cost: 12.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :google_gemini_3_1_flash_lite,
          api_name: "gemini-3.1-flash-lite",
          input_token_cost: 0.25 / 1_000_000,
          output_token_cost: 1.5 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :google_gemini_3_0_flash,
          api_name: "gemini-3-flash-preview",
          input_token_cost: 0.5 / 1_000_000,
          output_token_cost: 3.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :google_gemini_2_5_pro,
          api_name: "gemini-2.5-pro",
          input_token_cost: 1.25 / 1_000_000,
          output_token_cost: 10.0 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :google_gemini_2_5_flash,
          api_name: "gemini-2.5-flash",
          input_token_cost: 0.3 / 1_000_000,
          output_token_cost: 2.5 / 1_000_000,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        }
      ]
    }
  end

  def self.default_streaming_unsupported_model_keys
    [
      "bedrock_gpt_oss_120b",
      "bedrock_gpt_oss_20b"
    ].freeze
  end
end
