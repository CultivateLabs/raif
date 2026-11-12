# frozen_string_literal: true

provider :google do |p|
  p.references(
    models_doc: "https://ai.google.dev/gemini-api/docs/models",
    pricing: "https://ai.google.dev/gemini-api/docs/pricing",
    deprecations: "https://ai.google.dev/gemini-api/docs/deprecations",
    api_versions: "https://aistudio.google.com/api-reference/api-versions"
  )

  p.model(
    key: :google_gemini_4_carbon,
    api_name: "gemini-4-carbon",
    display_name: "Google Gemini 4 Carbon",
    max_completion_tokens: 65_536,
    batch_max_completion_tokens: 32_768,
    pricing: {
      cache_read_per_million: 0.1,
      input_per_million: 2.0,
      output_per_million: 10.0,
      note: "Introductory rate through 2026-11-30; followed_by is Google's standard rate from 2026-12-01",
      valid_until: Date.new(2026, 11, 30),
      followed_by: { cache_read_per_million: 0.2, input_per_million: 4.0, output_per_million: 20.0 }
    },
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
      status: :active,
      added_on: Date.new(2026, 11, 11)
    }
  )

  p.model(
    key: :google_gemini_4_argon,
    api_name: "gemini-4-argon",
    display_name: "Google Gemini 4 Argon",
    max_completion_tokens: 65_536,
    batch_max_completion_tokens: 32_768,
    pricing: {
      cache_read_per_million: 0.1,
      input_per_million: 2.0,
      output_per_million: 10.0,
      note: "Introductory rate through 2026-11-30; followed_by is Google's standard rate from 2026-12-01",
      valid_until: Date.new(2026, 11, 30),
      followed_by: { cache_read_per_million: 0.2, input_per_million: 4.0, output_per_million: 20.0 }
    },
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
      status: :active,
      added_on: Date.new(2026, 10, 14)
    }
  )

  p.model(
    key: :google_gemini_3_8_flash,
    api_name: "gemini-3.8-flash",
    display_name: "Google Gemini 3.8 Flash",
    max_completion_tokens: 65_536,
    pricing: {
      input_per_million: 0.75,
      output_per_million: 3.75,
      note: "Introductory rate through 2026-12-31; followed_by is Google's standard rate from 2027-01-01",
      valid_until: Date.new(2026, 12, 31),
      followed_by: { input_per_million: 1.5, output_per_million: 7.5 }
    },
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
      status: :active,
      added_on: Date.new(2026, 9, 14)
    }
  )

  p.model(
    key: :google_gemini_3_7_flash,
    api_name: "gemini-3.7-flash",
    display_name: "Google Gemini 3.7 Flash",
    pricing: {
      input_per_million: 0.75,
      output_per_million: 3.75,
      note: "Introductory rate through 2026-12-31; followed_by is Google's standard rate from 2027-01-01",
      valid_until: Date.new(2026, 12, 31),
      followed_by: { input_per_million: 1.5, output_per_million: 7.5 }
    },
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
      status: :deprecated,
      added_on: Date.new(2026, 8, 26),
      deprecated_on: Date.new(2026, 11, 10),
      retirement_date: Date.new(2026, 12, 1),
      replacement_key: :google_gemini_3_8_flash,
      migration_note: "As of 2026-11-10, Google's deprecations page says requests to gemini-3.7-flash are routed to gemini-3.8-flash, " \
        "and its pricing page no longer lists gemini-3.7-flash, so recorded costs may not match the bill."
    }
  )

  p.model(
    key: :google_gemini_3_6_flash,
    api_name: "gemini-3.6-flash",
    display_name: "Google Gemini 3.6 Flash",
    pricing: {
      input_per_million: 0.75,
      output_per_million: 3.75,
      note: "Introductory rate through 2026-12-31; followed_by is Google's standard rate from 2027-01-01",
      valid_until: Date.new(2026, 12, 31),
      followed_by: { input_per_million: 1.5, output_per_million: 7.5 }
    },
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
      status: :active,
      added_on: Date.new(2026, 8, 26)
    }
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
      status: :deprecated,
      deprecated_on: Date.new(2026, 11, 10),
      retirement_date: Date.new(2026, 12, 1),
      replacement_key: :google_gemini_3_6_flash,
      migration_note: "As of 2026-11-10, Google's deprecations page says requests to gemini-3.5-flash are routed to gemini-3.6-flash, " \
        "and its pricing page no longer lists gemini-3.5-flash, so recorded costs may not match the bill."
    }
  )

  p.model(
    key: :google_gemini_3_5_flash_lite,
    api_name: "gemini-3.5-flash-lite",
    display_name: "Google Gemini 3.5 Flash-Lite",
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
      status: :active,
      added_on: Date.new(2026, 8, 26)
    }
  )

  p.model(
    key: :google_gemini_3_1_pro,
    api_name: "gemini-3.1-pro-preview",
    display_name: "Google Gemini 3.1 Pro",
    pricing: {
      cache_read_per_million: 0.2,
      input_per_million: 2.0,
      output_per_million: 12.0,
      note: "Above 200K input tokens, input and cache rates double to 4.00 input / 0.40 cached input per million " \
        "and output rises to 18.00 per million."
    },
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
      status: :deprecated,
      deprecated_on: Date.new(2026, 9, 21),
      retirement_date: Date.new(2027, 5, 7),
      replacement_key: :google_gemini_3_5_flash_lite
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
    pricing: {
      cache_read_per_million: 0.125,
      input_per_million: 1.25,
      output_per_million: 10.0,
      note: "Above 200K input tokens, input and cache rates double to 2.50 input / 0.25 cached input per million " \
        "and output rises to 15.00 per million."
    },
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
      status: :deprecated,
      deprecated_on: Date.new(2026, 11, 9),
      retirement_date: Date.new(2026, 12, 1),
      replacement_key: :google_gemini_3_8_flash,
      migration_note: "From 2026-12-01 Google routes gemini-2.5-pro requests to gemini-3.8-flash and bills them at " \
        "Gemini 3.8 Flash rates; Raif removes this key after that date."
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
      status: :deprecated,
      deprecated_on: Date.new(2026, 11, 9),
      retirement_date: Date.new(2026, 12, 1),
      replacement_key: :google_gemini_3_5_flash_lite,
      migration_note: "From 2026-12-01 Google routes gemini-2.5-flash requests to gemini-3.5-flash-lite and bills them at " \
        "Gemini 3.5 Flash Lite rates; Raif removes this key after that date."
    }
  )
end
