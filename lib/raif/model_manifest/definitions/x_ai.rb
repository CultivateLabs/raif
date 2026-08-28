# frozen_string_literal: true

provider :x_ai do |p|
  p.references(
    models_doc: "https://docs.x.ai/docs/models",
    pricing: "https://docs.x.ai/docs/models",
    deprecations: "https://docs.x.ai/docs/models"
  )

  p.model(
    key: :x_ai_grok_4_5,
    api_name: "grok-4.5",
    display_name: "xAI Grok 4.5",
    pricing: { input_per_million: 2.0, output_per_million: 6.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :x_ai_grok_4_3,
    api_name: "grok-4.3",
    display_name: "xAI Grok 4.3",
    pricing: { input_per_million: 1.25, output_per_million: 2.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :x_ai_grok_4_20_reasoning,
    api_name: "grok-4.20-0309-reasoning",
    display_name: "xAI Grok 4.20 (reasoning)",
    pricing: { input_per_million: 1.25, output_per_million: 2.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :x_ai_grok_4_20_non_reasoning,
    api_name: "grok-4.20-0309-non-reasoning",
    display_name: "xAI Grok 4.20 (non-reasoning)",
    pricing: { input_per_million: 1.25, output_per_million: 2.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: true,
      images: true,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )
end
