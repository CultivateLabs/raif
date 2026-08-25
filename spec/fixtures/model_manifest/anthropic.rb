# frozen_string_literal: true

provider :anthropic do |p|
  p.references(
    models_doc: "https://docs.claude.com/en/docs/about-claude/models",
    pricing: "https://claude.com/pricing",
    deprecations: "https://docs.claude.com/en/docs/about-claude/model-deprecations"
  )

  p.model(
    key: :anthropic_test_model,
    api_name: "claude-test-1",
    display_name: "Anthropic Test Model",
    max_completion_tokens: 64_000,
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
      status: :active,
      added_on: Date.new(2025, 11, 24)
    }
  )

  p.model(
    key: :anthropic_old_model,
    api_name: "claude-old-1",
    display_name: "Anthropic Old Model",
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
      provider_managed_tools: []
    },
    lifecycle: {
      status: :deprecated,
      added_on: Date.new(2024, 1, 1),
      deprecated_on: Date.new(2026, 6, 1),
      retirement_date: Date.new(2026, 12, 1),
      replacement_key: :anthropic_test_model
    }
  )
end
