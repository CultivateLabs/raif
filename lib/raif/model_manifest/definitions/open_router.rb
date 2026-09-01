# frozen_string_literal: true

provider :open_router do |p|
  p.references(
    models_doc: "https://openrouter.ai/models",
    pricing: "https://openrouter.ai/models",
    deprecations: "https://openrouter.ai/docs/models"
  )

  p.model(
    key: :open_router_claude_5_fable,
    api_name: "anthropic/claude-fable-5",
    display_name: "Anthropic Claude Fable 5 (via OpenRouter)",
    pricing: { input_per_million: 10.0, output_per_million: 50.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_claude_4_8_opus,
    api_name: "anthropic/claude-opus-4.8",
    display_name: "Anthropic Claude 4.8 Opus (via OpenRouter)",
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_claude_5_sonnet,
    api_name: "anthropic/claude-sonnet-5",
    display_name: "Anthropic Claude 5 Sonnet (via OpenRouter)",
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: false,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_deepseek_chat_v3,
    api_name: "deepseek/deepseek-chat-v3-0324",
    display_name: "DeepSeek Chat v3 (via OpenRouter)",
    pricing: { input_per_million: 0.2, output_per_million: 0.77 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_deepseek_v3_1,
    api_name: "deepseek/deepseek-chat-v3.1",
    display_name: "DeepSeek v3.1 (via OpenRouter)",
    pricing: { input_per_million: 0.25, output_per_million: 1.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_deepseek_v3_2,
    api_name: "deepseek/deepseek-v3.2",
    display_name: "DeepSeek v3.2 (via OpenRouter)",
    pricing: { input_per_million: 0.26, output_per_million: 0.38 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_gemini_2_5_flash,
    api_name: "google/gemini-2.5-flash",
    display_name: "Gemini 2.5 Flash (via OpenRouter)",
    pricing: { input_per_million: 0.3, output_per_million: 2.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_gemini_3_5_flash,
    api_name: "google/gemini-3.5-flash",
    display_name: "Gemini 3.5 Flash (via OpenRouter)",
    pricing: { input_per_million: 1.5, output_per_million: 9.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_gemini_2_5_pro,
    api_name: "google/gemini-2.5-pro",
    display_name: "Gemini 2.5 Pro (via OpenRouter)",
    pricing: { input_per_million: 1.25, output_per_million: 10.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_gemini_3_1_pro_preview,
    api_name: "google/gemini-3.1-pro-preview",
    display_name: "Gemini 3.1 Pro Preview (via OpenRouter)",
    pricing: { input_per_million: 2.0, output_per_million: 12.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_gemini_3_1_flash_lite_preview,
    api_name: "google/gemini-3.1-flash-lite-preview",
    display_name: "Gemini 3.1 Flash-Lite Preview (via OpenRouter)",
    pricing: { input_per_million: 0.25, output_per_million: 1.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_glm_5_2,
    api_name: "z-ai/glm-5.2",
    display_name: "GLM 5.2 (via OpenRouter)",
    pricing: {
      input_per_million: 0.4186,
      output_per_million: 1.316,
      note: "70% off promotional price shown on openrouter.ai as of 2026-09-01 (base 1.19 in / 3.74 out); no end date documented"
    },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active,
      added_on: Date.new(2026, 9, 1)
    }
  )

  p.model(
    key: :open_router_glm_5_3,
    api_name: "z-ai/glm-5.3",
    display_name: "GLM 5.3 (via OpenRouter)",
    pricing: {
      input_per_million: 1.17,
      output_per_million: 3.96,
      note: "10% off promotional price shown on openrouter.ai as of 2026-09-01 (base 1.40 in / 4.40 out); no end date documented"
    },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active,
      added_on: Date.new(2026, 9, 1)
    }
  )

  p.model(
    key: :open_router_glm_5_3_flash,
    api_name: "z-ai/glm-5.3-flash",
    display_name: "GLM 5.3 Flash (via OpenRouter)",
    pricing: {
      input_per_million: 0.075,
      output_per_million: 0.25,
      note: "50% off promotional price shown on openrouter.ai as of 2026-09-01; no end date documented"
    },
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
      status: :active,
      added_on: Date.new(2026, 9, 1)
    }
  )

  p.model(
    key: :open_router_kimi_k2_thinking,
    api_name: "moonshotai/kimi-k2-thinking",
    display_name: "Kimi K2 Thinking (via OpenRouter)",
    pricing: { input_per_million: 0.45, output_per_million: 2.35 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_kimi_k2_5,
    api_name: "moonshotai/kimi-k2.5",
    display_name: "Kimi K2.5 (via OpenRouter)",
    pricing: { input_per_million: 0.45, output_per_million: 2.2 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_llama_3_3_70b_instruct,
    api_name: "meta-llama/llama-3.3-70b-instruct",
    display_name: "Meta Llama 3.3 70B Instruct (via OpenRouter)",
    pricing: { input_per_million: 0.1, output_per_million: 0.25 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_llama_3_1_8b_instruct,
    api_name: "meta-llama/llama-3.1-8b-instruct",
    display_name: "Meta Llama 3.1 8B Instruct (via OpenRouter)",
    pricing: { input_per_million: 0.02, output_per_million: 0.03 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_llama_4_maverick,
    api_name: "meta-llama/llama-4-maverick",
    display_name: "Meta Llama 4 Maverick (via OpenRouter)",
    pricing: { input_per_million: 0.15, output_per_million: 0.6 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_llama_4_scout,
    api_name: "meta-llama/llama-4-scout",
    display_name: "Meta Llama 4 Scout (via OpenRouter)",
    pricing: { input_per_million: 0.08, output_per_million: 0.3 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_minimax_m2,
    api_name: "minimax/minimax-m2",
    display_name: "Minimax M2 (via OpenRouter)",
    pricing: { input_per_million: 0.255, output_per_million: 1.02 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_minimax_m2_1,
    api_name: "minimax/minimax-m2.1",
    display_name: "Minimax M2.1 (via OpenRouter)",
    pricing: { input_per_million: 0.27, output_per_million: 0.95 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_minimax_m2_5,
    api_name: "minimax/minimax-m2.5",
    display_name: "Minimax M2.5 (via OpenRouter)",
    pricing: { input_per_million: 0.27, output_per_million: 0.95 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_mistral_large_3_2512,
    api_name: "mistralai/mistral-large-2512",
    display_name: "Mistral Large 3 (via OpenRouter)",
    pricing: { input_per_million: 0.5, output_per_million: 1.5 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_mistral_small_3_2_24b,
    api_name: "mistralai/mistral-small-3.2-24b-instruct",
    display_name: "Mistral Small 3.2 24B (via OpenRouter)",
    pricing: { input_per_million: 0.06, output_per_million: 0.18 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_open_ai_gpt_oss_120b,
    api_name: "gpt-oss-120b",
    display_name: "OpenAI GPT-OSS 120B (via OpenRouter)",
    pricing: { input_per_million: 0.15, output_per_million: 0.6 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_open_ai_gpt_oss_20b,
    api_name: "gpt-oss-20b",
    display_name: "OpenAI GPT-OSS 20B (via OpenRouter)",
    pricing: { input_per_million: 0.05, output_per_million: 0.2 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_grok_4_20,
    api_name: "x-ai/grok-4.20",
    display_name: "Grok 4.20 (via OpenRouter)",
    pricing: { input_per_million: 2.0, output_per_million: 6.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_grok_4_5,
    api_name: "x-ai/grok-4.5",
    display_name: "Grok 4.5 (via OpenRouter)",
    pricing: { input_per_million: 2.0, output_per_million: 6.0 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )

  p.model(
    key: :open_router_google_gemma_4_31b_it,
    api_name: "google/gemma-4-31b-it",
    display_name: "Google Gemma 4 31B IT (via OpenRouter)",
    pricing: { input_per_million: 0.14, output_per_million: 0.4 },
    capabilities: {
      temperature: true,
      structured_outputs: true,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active
    }
  )
end
