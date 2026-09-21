# frozen_string_literal: true

provider :bedrock do |p|
  p.references(
    mantle_api: "https://docs.aws.amazon.com/bedrock/latest/userguide/inference-chat-completions-mantle.html",
    model_cards: "https://docs.aws.amazon.com/bedrock/latest/userguide/model-cards.html",
    regional_lifecycle: "https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html",
    models_doc: "https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html",
    pricing: "https://aws.amazon.com/bedrock/pricing/",
    deprecations: "https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html"
  )

  p.model(
    key: :bedrock_claude_5_opus,
    api_name: "anthropic.claude-opus-5",
    display_name: "Anthropic Claude 5 Opus (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      input_per_million: 5.5,
      output_per_million: 27.5,
      note: "Regional inference rate including the 10% premium; global routing costs 5.00 / 25.00 per million."
    },
    capabilities: {
      temperature: false,
      structured_outputs: false,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active,
      added_on: Date.new(2026, 9, 14)
    }
  )

  p.model(
    key: :bedrock_claude_5_1_fable,
    api_name: "anthropic.claude-fable-5-1",
    display_name: "Anthropic Claude Fable 5.1 (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 0.275,
      input_per_million: 11.0,
      output_per_million: 55.0,
      note: "Regional inference rate including the 10% premium; global routing costs 10.00 / 50.00 per million."
    },
    capabilities: {
      temperature: false,
      structured_outputs: false,
      native_tool_use: true,
      forced_tool_choice: false,
      required_tool_choice: false,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :active,
      added_on: Date.new(2026, 9, 14)
    }
  )

  p.model(
    key: :bedrock_grok_4_3,
    adapter: :mantle,
    api_name: "xai.grok-4.3",
    display_name: "xAI Grok 4.3 (via AWS Bedrock Mantle)",
    pricing: { cache_read_per_million: 0.2, input_per_million: 1.25, output_per_million: 2.5 },
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
      added_on: Date.new(2026, 9, 14)
    }
  )

  p.model(
    key: :bedrock_grok_4_6,
    adapter: :mantle,
    api_name: "xai.grok-4.6",
    display_name: "xAI Grok 4.6 (via AWS Bedrock Mantle)",
    pricing: { cache_read_per_million: 0.55, input_per_million: 2.2, output_per_million: 6.6 },
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
      added_on: Date.new(2026, 9, 14)
    }
  )

  p.model(
    key: :bedrock_claude_5_fable,
    api_name: "anthropic.claude-fable-5",
    display_name: "Anthropic Claude Fable 5 (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 10.0, output_per_million: 50.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_4_8_opus,
    api_name: "anthropic.claude-opus-4-8",
    display_name: "Anthropic Claude 4.8 Opus (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_5_sonnet,
    api_name: "anthropic.claude-sonnet-5",
    display_name: "Anthropic Claude 5 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_4_7_opus,
    api_name: "anthropic.claude-opus-4-7",
    display_name: "Anthropic Claude 4.7 Opus (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_4_6_opus,
    api_name: "anthropic.claude-opus-4-6-v1",
    display_name: "Anthropic Claude 4.6 Opus (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
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
    key: :bedrock_claude_4_6_sonnet,
    api_name: "anthropic.claude-sonnet-4-6",
    display_name: "Anthropic Claude 4.6 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
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
    key: :bedrock_claude_4_5_opus,
    api_name: "anthropic.claude-opus-4-5-20251101-v1:0",
    display_name: "Anthropic Claude 4.5 Opus (via AWS Bedrock)",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 5.0, output_per_million: 25.0 },
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
    key: :bedrock_claude_4_5_sonnet,
    api_name: "anthropic.claude-sonnet-4-5-20250929-v1:0",
    display_name: "Anthropic Claude 4.5 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
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
    key: :bedrock_claude_4_5_haiku,
    api_name: "anthropic.claude-haiku-4-5-20251001-v1:0",
    display_name: "Anthropic Claude 4.5 Haiku (via AWS Bedrock)",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 1.0, output_per_million: 5.0 },
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
    key: :bedrock_claude_4_1_opus,
    api_name: "anthropic.claude-opus-4-1-20250805-v1:0",
    display_name: "Claude 4.1 Opus (via AWS Bedrock)",
    max_completion_tokens: 32_000,
    pricing: { input_per_million: 15.0, output_per_million: 75.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_4_sonnet,
    api_name: "anthropic.claude-sonnet-4-20250514-v1:0",
    display_name: "Anthropic Claude 4 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 64_000,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_claude_3_7_sonnet,
    api_name: "anthropic.claude-3-7-sonnet-20250219-v1:0",
    display_name: "Anthropic Claude 3.7 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 8192,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :retired,
      retirement_date: Date.new(2026, 7, 30),
      replacement_key: :bedrock_claude_5_sonnet,
      migration_note: "Retired from Raif on 2026-09-14 after the US inference-profile end-of-life on 2026-07-30, the removal " \
        "date announced in the v1.5.0 changelog; a few non-US regions still list the model. Migrate to Claude Sonnet 5."
    }
  )

  p.model(
    key: :bedrock_claude_3_5_sonnet,
    api_name: "anthropic.claude-3-5-sonnet-20241022-v2:0",
    display_name: "Anthropic Claude 3.5 Sonnet (via AWS Bedrock)",
    max_completion_tokens: 8192,
    pricing: { input_per_million: 3.0, output_per_million: 15.0 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: true,
      batch_inference: false,
      images: true,
      pdfs: true,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :retired,
      retirement_date: Date.new(2026, 7, 30),
      replacement_key: :bedrock_claude_5_sonnet,
      migration_note: "Retired from Raif on 2026-09-14 after the US inference-profile end-of-life on 2026-07-30, the removal " \
        "date announced in the v1.5.0 changelog; a few non-US regions still list the model. Migrate to Claude Sonnet 5."
    }
  )

  p.model(
    key: :bedrock_amazon_nova_micro,
    api_name: "amazon.nova-micro-v1:0",
    display_name: "Amazon Nova Micro (via AWS Bedrock)",
    max_completion_tokens: 4096,
    pricing: { input_per_million: 0.0115, output_per_million: 0.184 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_amazon_nova_lite,
    api_name: "amazon.nova-lite-v1:0",
    display_name: "Amazon Nova Lite (via AWS Bedrock)",
    max_completion_tokens: 4096,
    pricing: { input_per_million: 0.0195, output_per_million: 0.312 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_amazon_nova_pro,
    api_name: "amazon.nova-pro-v1:0",
    display_name: "Amazon Nova Pro (via AWS Bedrock)",
    max_completion_tokens: 4096,
    pricing: { input_per_million: 0.2625, output_per_million: 4.2 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
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
    key: :bedrock_deepseek_v3_2,
    api_name: "deepseek.v3.2",
    display_name: "DeepSeek v3.2 (via AWS Bedrock)",
    max_completion_tokens: 8192,
    pricing: { input_per_million: 0.62, output_per_million: 1.85 },
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
    key: :bedrock_deepseek_r1,
    api_name: "us.deepseek.r1-v1:0",
    display_name: "DeepSeek R1 (via AWS Bedrock)",
    max_completion_tokens: 8192,
    pricing: { input_per_million: 1.35, output_per_million: 5.4 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: false,
      streaming: true,
      batch_inference: false,
      images: false,
      pdfs: false,
      provider_managed_tools: []
    },
    lifecycle: {
      status: :deprecated,
      deprecated_on: Date.new(2026, 9, 1),
      retirement_date: Date.new(2026, 9, 30),
      replacement_key: :bedrock_deepseek_v3_2,
      migration_note: "AWS documents DeepSeek-R1's EOL as no sooner than 2026-03-10, a date now passed, so AWS may " \
        "retire it with notice at any time. Raif removes this entry on 2026-09-30. DeepSeek v3.2 on Bedrock is " \
        "newer, cheaper, and supports tool calling and structured outputs."
    }
  )

  p.model(
    key: :bedrock_gpt_oss_120b,
    api_name: "openai.gpt-oss-120b-1:0",
    display_name: "OpenAI GPT-OSS 120B (via AWS Bedrock)",
    max_completion_tokens: 32_768,
    pricing: { input_per_million: 0.15, output_per_million: 0.6 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: false,
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
    key: :bedrock_gpt_oss_20b,
    api_name: "openai.gpt-oss-20b-1:0",
    display_name: "OpenAI GPT-OSS 20B (via AWS Bedrock)",
    max_completion_tokens: 32_768,
    pricing: { input_per_million: 0.07, output_per_million: 0.3 },
    capabilities: {
      temperature: true,
      structured_outputs: false,
      native_tool_use: true,
      streaming: false,
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
    key: :bedrock_gpt_6_astra,
    api_name: "openai.gpt-6-astra",
    display_name: "OpenAI GPT-6 Astra (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 1.1,
      input_per_million: 11.0,
      output_per_million: 55.0,
      note: "Regional and US geo inference rate including the 10% fee; global routing costs 10.00 / 50.00 per million. Above 272K input tokens, " \
        "the full request costs 22.00 / 82.50 per million."
    },
    capabilities: {
      temperature: false,
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
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_gpt_5_6_sol,
    api_name: "openai.gpt-5.6-sol",
    display_name: "OpenAI GPT-5.6 Sol (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 0.44,
      input_per_million: 4.4,
      output_per_million: 22.0,
      note: "Regional and US geo inference rate including the 10% fee; global routing costs 4.00 / 20.00 per million. Above 272K input tokens, the " \
        "full request costs 8.80 / 33.00 per million."
    },
    capabilities: {
      temperature: false,
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
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_gpt_5_6_terra,
    api_name: "openai.gpt-5.6-terra",
    display_name: "OpenAI GPT-5.6 Terra (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 0.22,
      input_per_million: 2.2,
      output_per_million: 13.2,
      note: "Regional and US geo inference rate including the 10% fee; global routing costs 2.00 / 12.00 per million. Above 272K input tokens, the " \
        "full request costs 4.40 / 19.80 per million."
    },
    capabilities: {
      temperature: false,
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
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_gpt_5_6_luna,
    api_name: "openai.gpt-5.6-luna",
    display_name: "OpenAI GPT-5.6 Luna (via AWS Bedrock)",
    max_completion_tokens: 128_000,
    pricing: {
      cache_read_per_million: 0.022,
      input_per_million: 0.22,
      output_per_million: 1.32,
      note: "Regional and US geo inference rate including the 10% fee; global routing costs 0.20 / 1.20 per million. Above 272K input tokens, the " \
        "full request costs 0.44 / 1.98 per million."
    },
    capabilities: {
      temperature: false,
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
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_gpt_oss_safeguard_120b,
    api_name: "openai.gpt-oss-safeguard-120b",
    display_name: "OpenAI GPT-OSS Safeguard 120B (via AWS Bedrock)",
    max_completion_tokens: 32_768,
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
      status: :active,
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_gpt_oss_safeguard_20b,
    api_name: "openai.gpt-oss-safeguard-20b",
    display_name: "OpenAI GPT-OSS Safeguard 20B (via AWS Bedrock)",
    max_completion_tokens: 32_768,
    pricing: { input_per_million: 0.07, output_per_million: 0.2 },
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
      added_on: Date.new(2026, 9, 21)
    }
  )

  p.model(
    key: :bedrock_deepseek_v3_1,
    api_name: "deepseek.v3-v1:0",
    display_name: "DeepSeek V3.1 (via AWS Bedrock)",
    max_completion_tokens: 8192,
    pricing: {
      input_per_million: 0.58,
      output_per_million: 1.68,
      note: "Standard on-demand rate in US West (Oregon). Bedrock does not offer this model in us-east-1, raif's default aws_bedrock_region, so " \
        "set the region to us-west-2 or us-east-2 before using this key."
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
      added_on: Date.new(2026, 9, 21)
    }
  )
end
