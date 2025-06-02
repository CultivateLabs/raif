# frozen_string_literal: true

module Raif
  def self.llm_registry
    @llm_registry ||= {}
  end

  def self.register_llm(llm_class, llm_config)
    llm = llm_class.new(**llm_config)

    unless llm.valid?
      raise ArgumentError, "The LLM you tried to register is invalid: #{llm.errors.full_messages.join(", ")}"
    end

    @llm_registry ||= {}
    @llm_registry[llm.key] = llm_config.merge(llm_class: llm_class)
  end

  def self.llm(model_key)
    llm_config = llm_registry[model_key]

    if llm_config.nil?
      raise ArgumentError, "No LLM found for model key: #{model_key}. Available models: #{available_llm_keys.join(", ")}"
    end

    llm_class = llm_config[:llm_class]
    llm_class.new(**llm_config.except(:llm_class))
  end

  def self.available_llms
    llm_registry.values
  end

  def self.available_llm_keys
    llm_registry.keys
  end

  def self.llm_config(model_key)
    llm_registry[model_key]
  end

  def self.default_llms
    open_ai_models = [
      {
        key: :open_ai_gpt_4o_mini,
        api_name: "gpt-4o-mini",
        input_token_cost: 0.15 / 1_000_000,
        output_token_cost: 0.6 / 1_000_000,
      },
      {
        key: :open_ai_gpt_4o,
        api_name: "gpt-4o",
        input_token_cost: 2.5 / 1_000_000,
        output_token_cost: 10.0 / 1_000_000,
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
        output_token_cost: 8.0 / 1_000_000,
      },
      {
        key: :open_ai_gpt_4_1_mini,
        api_name: "gpt-4.1-mini",
        input_token_cost: 0.4 / 1_000_000,
        output_token_cost: 1.6 / 1_000_000,
      },
      {
        key: :open_ai_gpt_4_1_nano,
        api_name: "gpt-4.1-nano",
        input_token_cost: 0.1 / 1_000_000,
        output_token_cost: 0.4 / 1_000_000,
      },
    ]

    open_ai_responses_models = open_ai_models.dup.map.with_index do |model, _index|
      model.merge(
        key: model[:key].to_s.gsub("open_ai_", "open_ai_responses_").to_sym,
        supported_provider_managed_tools: [
          Raif::ModelTools::ProviderManaged::WebSearch,
          Raif::ModelTools::ProviderManaged::CodeExecution,
          Raif::ModelTools::ProviderManaged::ImageGeneration
        ]
      )
    end

    {
      Raif::Llms::OpenAiCompletions => open_ai_models,
      Raif::Llms::OpenAiResponses => open_ai_responses_models,
      Raif::Llms::Anthropic => [
        {
          key: :anthropic_claude_4_sonnet,
          api_name: "claude-sonnet-4-20250514",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 8192,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_4_opus,
          api_name: "claude-opus-4-20250514",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 75.0 / 1_000_000,
          max_completion_tokens: 8192,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_3_7_sonnet,
          api_name: "claude-3-7-sonnet-latest",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 8192,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_3_5_sonnet,
          api_name: "claude-3-5-sonnet-latest",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
          max_completion_tokens: 8192,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_3_5_haiku,
          api_name: "claude-3-5-haiku-latest",
          input_token_cost: 0.8 / 1_000_000,
          output_token_cost: 4.0 / 1_000_000,
          max_completion_tokens: 8192,
          supported_provider_managed_tools: [
            Raif::ModelTools::ProviderManaged::WebSearch,
            Raif::ModelTools::ProviderManaged::CodeExecution
          ]
        },
        {
          key: :anthropic_claude_3_opus,
          api_name: "claude-3-opus-latest",
          input_token_cost: 15.0 / 1_000_000,
          output_token_cost: 75.0 / 1_000_000,
          max_completion_tokens: 4096
        },
      ],
      Raif::Llms::Bedrock => [
        {
          key: :bedrock_claude_4_sonnet,
          api_name: "anthropic.claude-sonnet-4-20250514-v1:0",
          input_token_cost: 0.003 / 1000,
          output_token_cost: 0.015 / 1000,
          max_completion_tokens: 8192
        },
        {
          key: :bedrock_claude_4_opus,
          api_name: "anthropic.claude-opus-4-20250514-v1:0",
          input_token_cost: 0.015 / 1000,
          output_token_cost: 0.075 / 1000,
          max_completion_tokens: 8192
        },
        {
          key: :bedrock_claude_3_5_sonnet,
          api_name: "anthropic.claude-3-5-sonnet-20241022-v2:0",
          input_token_cost: 0.003 / 1000,
          output_token_cost: 0.015 / 1000,
          max_completion_tokens: 8192
        },
        {
          key: :bedrock_claude_3_7_sonnet,
          api_name: "anthropic.claude-3-7-sonnet-20250219-v1:0",
          input_token_cost: 0.003 / 1000,
          output_token_cost: 0.015 / 1000,
          max_completion_tokens: 8192
        },
        {
          key: :bedrock_claude_3_5_haiku,
          api_name: "anthropic.claude-3-5-haiku-20241022-v1:0",
          input_token_cost: 0.0008 / 1000,
          output_token_cost: 0.004 / 1000,
          max_completion_tokens: 8192
        },
        {
          key: :bedrock_claude_3_opus,
          api_name: "anthropic.claude-3-opus-20240229-v1:0",
          input_token_cost: 0.015 / 1000,
          output_token_cost: 0.075 / 1000,
          max_completion_tokens: 4096
        },
        {
          key: :bedrock_amazon_nova_micro,
          api_name: "amazon.nova-micro-v1:0",
          input_token_cost: 0.0000115 / 1000,
          output_token_cost: 0.000184 / 1000,
          max_completion_tokens: 4096
        },
        {
          key: :bedrock_amazon_nova_lite,
          api_name: "amazon.nova-lite-v1:0",
          input_token_cost: 0.0000195 / 1000,
          output_token_cost: 0.000312 / 1000,
          max_completion_tokens: 4096
        },
        {
          key: :bedrock_amazon_nova_pro,
          api_name: "amazon.nova-pro-v1:0",
          input_token_cost: 0.0002625 / 1000,
          output_token_cost: 0.0042 / 1000,
          max_completion_tokens: 4096
        }
      ],
      Raif::Llms::OpenRouter => [
        {
          key: :open_router_claude_3_7_sonnet,
          api_name: "anthropic/claude-3.7-sonnet",
          input_token_cost: 3.0 / 1_000_000,
          output_token_cost: 15.0 / 1_000_000,
        },
        {
          key: :open_router_llama_3_3_70b_instruct,
          api_name: "meta-llama/llama-3.3-70b-instruct",
          input_token_cost: 0.10 / 1_000_000,
          output_token_cost: 0.25 / 1_000_000,
        },
        {
          key: :open_router_llama_3_1_8b_instruct,
          api_name: "meta-llama/llama-3.1-8b-instruct",
          input_token_cost: 0.02 / 1_000_000,
          output_token_cost: 0.03 / 1_000_000,
        },
        {
          key: :open_router_gemini_2_0_flash,
          api_name: "google/gemini-2.0-flash-001",
          input_token_cost: 0.1 / 1_000_000,
          output_token_cost: 0.4 / 1_000_000,
        },
        {
          key: :open_router_deepseek_chat_v3,
          api_name: "deepseek/deepseek-chat-v3-0324",
          input_token_cost: 0.27 / 1_000_000,
          output_token_cost: 1.1 / 1_000_000,
        },
      ]
    }
  end
end
