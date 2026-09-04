# frozen_string_literal: true

provider :google do |p|
  p.references(
    models_doc: "https://ai.google.dev/gemini-api/docs/models",
    pricing: "https://ai.google.dev/gemini-api/docs/pricing",
    deprecations: "https://ai.google.dev/gemini-api/docs/deprecations"
  )

  p.model(
    key: :google_gemini_3_5_flash,
    api_name: "gemini-3.5-flash",
    display_name: "Google Gemini 3.5 Flash",
    pricing: { input_per_million: 1.5, output_per_million: 9.0 },
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
    key: :google_gemini_3_1_pro,
    api_name: "gemini-3.1-pro-preview",
    display_name: "Google Gemini 3.1 Pro",
    pricing: { input_per_million: 2.0, output_per_million: 12.0 },
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
    key: :google_gemini_3_1_flash_lite,
    api_name: "gemini-3.1-flash-lite",
    display_name: "Google Gemini 3.1 Flash-Lite",
    pricing: { input_per_million: 0.25, output_per_million: 1.5 },
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
    key: :google_gemini_3_0_flash,
    api_name: "gemini-3-flash-preview",
    display_name: "Google Gemini 3 Flash",
    pricing: { input_per_million: 0.5, output_per_million: 3.0 },
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
    key: :google_gemini_2_5_pro,
    api_name: "gemini-2.5-pro",
    display_name: "Google Gemini 2.5 Pro",
    pricing: { input_per_million: 1.25, output_per_million: 10.0 },
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
    key: :google_gemini_2_5_flash,
    api_name: "gemini-2.5-flash",
    display_name: "Google Gemini 2.5 Flash",
    pricing: { input_per_million: 0.3, output_per_million: 2.5 },
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
end
