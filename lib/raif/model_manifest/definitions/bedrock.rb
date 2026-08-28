# frozen_string_literal: true

provider :bedrock do |p|
  p.references(
    models_doc: "https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html",
    pricing: "https://aws.amazon.com/bedrock/pricing/",
    deprecations: "https://docs.aws.amazon.com/bedrock/latest/userguide/model-lifecycle.html"
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
      status: :active
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
      status: :active
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
      images: true,
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
    max_completion_tokens: 32_768,
    pricing: { input_per_million: 0.62, output_per_million: 1.85 },
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
    key: :bedrock_deepseek_r1,
    api_name: "deepseek.r1-v1:0",
    display_name: "DeepSeek R1 (via AWS Bedrock)",
    max_completion_tokens: 32_768,
    pricing: { input_per_million: 1.35, output_per_million: 5.4 },
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
end
