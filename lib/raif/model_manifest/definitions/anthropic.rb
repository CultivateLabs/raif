# frozen_string_literal: true

provider :anthropic do |p|
  p.references(
    models_doc: "https://docs.claude.com/en/docs/about-claude/models",
    pricing: "https://claude.com/pricing",
    deprecations: "https://docs.claude.com/en/docs/about-claude/model-deprecations"
  )

  p.model(
    key: :anthropic_claude_5_fable,
    api_name: "claude-fable-5",
    display_name: "Anthropic Claude Fable 5",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 10.0, output_per_million: 50.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_8_opus,
    api_name: "claude-opus-4-8",
    display_name: "Anthropic Claude 4.8 Opus",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_5_sonnet,
    api_name: "claude-sonnet-5",
    display_name: "Anthropic Claude 5 Sonnet",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_7_opus,
    api_name: "claude-opus-4-7",
    display_name: "Anthropic Claude 4.7 Opus",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_6_opus,
    api_name: "claude-opus-4-6",
    display_name: "Anthropic Claude 4.6 Opus",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_6_sonnet,
    api_name: "claude-sonnet-4-6",
    display_name: "Anthropic Claude 4.6 Sonnet",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_5_opus,
    api_name: "claude-opus-4-5",
    display_name: "Anthropic Claude 4.5 Opus",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_5_sonnet,
    api_name: "claude-sonnet-4-5",
    display_name: "Anthropic Claude 4.5 Sonnet",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_5_haiku,
    api_name: "claude-haiku-4-5",
    display_name: "Anthropic Claude 4.5 Haiku",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 1.0, output_per_million: 5.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :anthropic_claude_4_1_opus,
    api_name: "claude-opus-4-1",
    display_name: "Anthropic Claude 4.1 Opus",
    max_completion_tokens: 32_000,
    pricing: { input_per_million: 15.0, output_per_million: 75.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: true,
      provider_managed_tools: %i[web_search code_execution]
    },
    lifecycle: {
      status: :active
    }
  )
end
