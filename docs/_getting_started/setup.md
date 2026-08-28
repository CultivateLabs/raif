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

You **must configure at least one API key** for an LLM provider ([OpenAI](#openai), [Anthropic](#anthropic), [AWS Bedrock](#aws-bedrock), [OpenRouter](#openrouter), [Google AI](#google-ai), [xAI](#xai)). 

By default, the initializer will load them from environment variables (e.g. `ENV["OPENAI_API_KEY"]`, `ENV["ANTHROPIC_API_KEY"]`, `ENV["OPEN_ROUTER_API_KEY"]`, `ENV["GOOGLE_AI_API_KEY"]`, `ENV["XAI_API_KEY"]`). Alternatively, you can set them directly in `config/initializers/raif.rb`.

## OpenAI

### OpenAI Responses API

Use this adapter to utilize OpenAI's newer [Responses API](https://platform.openai.com/docs/api-reference/responses){:target="_blank"}, which supports [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools), including web search, code execution, and image generation.

Note: OpenAI's [GPT-OSS models](https://openai.com/index/introducing-gpt-oss/){:target="_blank"} are not supported by OpenAI's API, but are available via [OpenRouter](#openrouter).

Raif sends `store: false` on every Responses API request, so OpenAI does not keep the response object. See [Provider Data Retention](../learn_more/provider_data_retention) for what that does and does not cover.

```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_responses_gpt_4o"
end
```

The OpenAI models Raif ships, with their pricing and capabilities, are defined in [`open_ai.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/open_ai.rb). Responses API keys use the `open_ai_responses_` prefix. `Raif.available_llm_keys` lists what your app has registered.

### OpenAI Completions API

This adapter utilizes OpenAI's legacy [Completions API](https://platform.openai.com/docs/api-reference/chat){:target="_blank"}. This API does not support [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) like web search, code execution, and image generation. To utilize those, use the newer [Responses API](#openai-responses-api) instead.

```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_gpt_4o"
end
```

Completions API keys use the `open_ai_` prefix and are defined in the same [`open_ai.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/open_ai.rb).

## Anthropic

The Anthropic adapter provides access to [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) for web search and code execution.

```ruby
Raif.configure do |config|
  config.anthropic_models_enabled = true
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_llm_model_key = "anthropic_claude_5_sonnet"
end
```

The Anthropic models Raif ships, with their pricing and capabilities, are defined in [`anthropic.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/anthropic.rb). `Raif.available_llm_keys` lists what your app has registered.

## AWS Bedrock

Note: Raif utilizes the [AWS Bedrock gem](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Client.html){:target="_blank"} and AWS credentials should be configured via the AWS SDK (environment variables, IAM role, etc.)

```ruby
Raif.configure do |config|
  config.bedrock_models_enabled = true
  config.aws_bedrock_region = "us-east-1"
  config.default_llm_model_key = "bedrock_claude_5_sonnet"
end
```

The Bedrock models Raif ships are defined in [`bedrock.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/bedrock.rb).

## OpenRouter
[OpenRouter](https://openrouter.ai/){:target="_blank"} is a unified API that provides access to multiple AI models from different providers including Anthropic, Meta, Google, and more.

See [Adding LLM Models](customization#adding-llm-models) for more information on adding new OpenRouter models to your application.

Raif sends `provider: { data_collection: "deny" }` on every OpenRouter request, so routing avoids providers that train on prompts. See [Provider Data Retention](../learn_more/provider_data_retention) for that setting and for zero data retention routing.

```ruby
Raif.configure do |config|
  config.open_router_models_enabled = true
  config.open_router_api_key = ENV["OPEN_ROUTER_API_KEY"]
  config.open_router_app_name = "Your App Name" # Optional
  config.open_router_site_url = "https://yourdomain.com" # Optional
  config.default_llm_model_key = "open_router_claude_5_sonnet"
end
```

The OpenRouter models Raif ships are defined in [`open_router.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/open_router.rb).

## Google AI

The Google AI adapter provides access to Google's Gemini models with support for [provider-managed tools](../key_raif_concepts/model_tools#provider-managed-tools) for web search and code execution.

When `tool_choice: :required` is used, Google can provider-enforce it only for developer-managed function tools. Requests that include Google provider-managed tools fall back to runtime validation and emit a warning.

```ruby
Raif.configure do |config|
  config.google_models_enabled = true
  config.google_api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GOOGLE_API_KEY"]
  config.default_llm_model_key = "google_gemini_2_5_flash"
end
```

The Google AI models Raif ships are defined in [`google.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/google.rb).

Google embedding models use the same API key, but remain opt-in. See [Embedding Models](../learn_more/embedding_models) to enable `config.google_embedding_models_enabled`.

## xAI

The xAI adapter provides access to [Grok models](https://docs.x.ai/docs/models){:target="_blank"} via xAI's chat completions API, with support for streaming, developer-managed tools, and [batch inference](../learn_more/task_batching).

```ruby
Raif.configure do |config|
  config.x_ai_models_enabled = true
  config.x_ai_api_key = ENV["XAI_API_KEY"].presence || ENV["X_AI_API_KEY"]
  config.default_llm_model_key = "x_ai_grok_4_3"
end
```

The xAI models Raif ships are defined in [`x_ai.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/x_ai.rb).

## Embedding Models

Raif also supports generating vector embeddings. See [Embedding Models](../learn_more/embedding_models) for configuration details and usage. The embedding models Raif ships are defined in [`embeddings.rb`](https://github.com/CultivateLabs/raif/blob/main/lib/raif/model_manifest/definitions/embeddings.rb). `Raif.available_embedding_model_keys` lists what your app has registered.

---

**Read next:** [Chatting with the LLM](chatting_with_the_llm)
