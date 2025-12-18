---
layout: default
title: Setup
nav_order: 2
description: "Setup Raif in your Rails application"
---

{% include table-of-contents.md %}

# Initial Setup

Add Raif to your application's Gemfile:

```ruby
gem "raif"
```

And then execute:
```bash
bundle install
```

Run the install generator:
```bash
rails generate raif:install
```

This will:
- Create a configuration file at `config/initializers/raif.rb`
- Copy Raif's database migrations to your application
- Mount Raif's engine at `/raif` in your application's `config/routes.rb` file

Next, run the migrations. Raif is compatible with both PostgreSQL and MySQL databases.
```bash
rails db:migrate
```

# Configuring LLM Providers & API Keys

You **must configure at least one API key** for an LLM provider ([OpenAI](#openai), [Anthropic](#anthropic), [AWS Bedrock](#aws-bedrock), [OpenRouter](#openrouter), [Google AI](#google-ai)). 

By default, the initializer will load them from environment variables (e.g. `ENV["OPENAI_API_KEY"]`, `ENV["ANTHROPIC_API_KEY"]`, `ENV["OPEN_ROUTER_API_KEY"]`). Alternatively, you can set them directly in `config/initializers/raif.rb`.

## OpenAI

### OpenAI Responses API

Use this adapter to utilize OpenAI's newer [Responses API](https://platform.openai.com/docs/api-reference/responses){:target="_blank"}, which supports [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools), including web search, code execution, and image generation.

Note: OpenAI's [GPT-OSS models](https://openai.com/index/introducing-gpt-oss/){:target="_blank"} are not supported by OpenAI's API, but are available via [OpenRouter](#openrouter).

```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_responses_gpt_4o"
end
```

Currently supported OpenAI Responses API models:
- `open_ai_responses_gpt_5`
- `open_ai_responses_gpt_5_mini`
- `open_ai_responses_gpt_5_nano`
- `open_ai_responses_gpt_3_5_turbo`
- `open_ai_responses_gpt_4_1`
- `open_ai_responses_gpt_4_1_mini`
- `open_ai_responses_gpt_4_1_nano`
- `open_ai_responses_gpt_4o`
- `open_ai_responses_gpt_4o_mini`
- `open_ai_responses_o1`
- `open_ai_responses_o1_mini`
- `open_ai_responses_o1_pro`
- `open_ai_responses_o3`
- `open_ai_responses_o3_mini`
- `open_ai_responses_o3_pro`
- `open_ai_responses_o4_mini`

### OpenAI Completions API

This adapter utilizes OpenAI's legacy [Completions API](https://platform.openai.com/docs/api-reference/chat){:target="_blank"}. This API does not support [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) like web search, code execution, and image generation. To utilize those, use the newer [Responses API](#openai-responses-api) instead.

```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_gpt_4o"
end
```

Currently supported OpenAI Completions API models:
- `open_ai_gpt_5`
- `open_ai_gpt_5_mini`
- `open_ai_gpt_5_nano`
- `open_ai_gpt_3_5_turbo`
- `open_ai_gpt_4_1`
- `open_ai_gpt_4_1_mini`
- `open_ai_gpt_4_1_nano`
- `open_ai_gpt_4o`
- `open_ai_gpt_4o_mini`
- `open_ai_o1`
- `open_ai_o1_mini`
- `open_ai_o3`
- `open_ai_o3_mini`
- `open_ai_o4_mini`


## Anthropic

The Anthropic adapter provides access to [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) for web search and code execution.

```ruby
Raif.configure do |config|
  config.anthropic_models_enabled = true
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_llm_model_key = "anthropic_claude_3_5_sonnet"
end
```

Currently supported Anthropic models:
- `anthropic_claude_3_5_haiku`
- `anthropic_claude_3_5_sonnet`
- `anthropic_claude_3_7_sonnet`
- `anthropic_claude_3_opus`
- `anthropic_claude_4_opus`
- `anthropic_claude_4_1_opus`
- `anthropic_claude_4_sonnet`
- `anthropic_claude_4_5_sonnet`

## AWS Bedrock

Note: Raif utilizes the [AWS Bedrock gem](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Client.html){:target="_blank"} and AWS credentials should be configured via the AWS SDK (environment variables, IAM role, etc.)

```ruby
Raif.configure do |config|
  config.bedrock_models_enabled = true
  config.aws_bedrock_region = "us-east-1"
  config.default_llm_model_key = "bedrock_claude_3_5_sonnet"
end
```

Currently supported Bedrock models:
- `bedrock_claude_3_5_haiku`
- `bedrock_claude_3_5_sonnet`
- `bedrock_claude_3_7_sonnet`
- `bedrock_claude_3_opus`
- `bedrock_claude_4_opus`
- `bedrock_claude_4_1_opus`
- `bedrock_claude_4_sonnet`
- `bedrock_claude_4_5_sonnet`
- `bedrock_amazon_nova_lite`
- `bedrock_amazon_nova_micro`
- `bedrock_amazon_nova_pro`

## OpenRouter
[OpenRouter](https://openrouter.ai/){:target="_blank"} is a unified API that provides access to multiple AI models from different providers including Anthropic, Meta, Google, and more.

See [Adding LLM Models](customization#adding-llm-models) for more information on adding new OpenRouter models to your application.

```ruby
Raif.configure do |config|
  config.open_router_models_enabled = true
  config.open_router_api_key = ENV["OPEN_ROUTER_API_KEY"]
  config.open_router_app_name = "Your App Name" # Optional
  config.open_router_site_url = "https://yourdomain.com" # Optional
  config.default_llm_model_key = "open_router_claude_3_7_sonnet"
end
```

Currently included OpenRouter models:
- `open_router_claude_3_7_sonnet`
- `open_router_deepseek_chat_v3`
- `open_router_gemini_2_0_flash`
- `open_router_llama_3_1_8b_instruct`
- `open_router_llama_3_3_70b_instruct`
- `open_router_llama_4_maverick`
- `open_router_llama_4_scout`
- `open_router_open_ai_gpt_oss_120b`
- `open_router_open_ai_gpt_oss_20b`

## Google AI

The Google AI adapter provides access to Google's Gemini models with support for [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) for web search and code execution.

```ruby
Raif.configure do |config|
  config.google_models_enabled = true
  config.google_api_key = ENV["GOOGLE_API_KEY"]
  config.default_llm_model_key = "google_gemini_2_5_flash"
end
```

Currently supported Google AI models:
- `google_gemini_2_5_flash`
- `google_gemini_2_5_pro`
- `google_gemini_3_0_flash`
- `google_gemini_3_0_pro`

---

**Read next:** [Chatting with the LLM](chatting_with_the_llm)