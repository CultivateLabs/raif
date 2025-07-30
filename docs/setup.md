---
layout: default
title: Setup
nav_order: 2
description: "Setup Raif in your Rails application"
---

# Setup

Add this line to your application's Gemfile:

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

You must configure at least one API key for your LLM provider ([OpenAI](#openai), [Anthropic Claude](#anthropic-claude), [AWS Bedrock](#aws-bedrock-claude), [OpenRouter](#openrouter)). By default, the initializer will load them from environment variables (e.g. `ENV["OPENAI_API_KEY"]`, `ENV["ANTHROPIC_API_KEY"]`, `ENV["OPENROUTER_API_KEY"]`). Alternatively, you can set them directly in `config/initializers/raif.rb`.

Run the migrations. Raif is compatible with both PostgreSQL and MySQL databases.
```bash
rails db:migrate
```

If you plan to use the [conversations](#conversations) feature or Raif's [web admin](#web-admin), configure authentication and authorization for Raif's controllers in `config/initializers/raif.rb`:

```ruby
Raif.configure do |config|
  # Configure who can access non-admin controllers
  # For example, to allow all logged in users:
  config.authorize_controller_action = ->{ current_user.present? }

  # Configure who can access admin controllers
  # For example, to allow users with admin privileges:
  config.authorize_admin_controller_action = ->{ current_user&.admin? }
end
```

Configure your LLM providers. You'll need at least one of:

## OpenAI

Raif supports both OpenAI's [Completions API](https://platform.openai.com/docs/api-reference/chat) and the newer [Responses API](https://platform.openai.com/docs/api-reference/responses), which provides access to provider-managed tools like web search, code execution, and image generation.

### OpenAI Completions API
```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_gpt_4o"
end
```

Currently supported OpenAI Completions API models:
- `open_ai_gpt_4o_mini`
- `open_ai_gpt_4o`
- `open_ai_gpt_3_5_turbo`
- `open_ai_gpt_4_1`
- `open_ai_gpt_4_1_mini`
- `open_ai_gpt_4_1_nano`
- `open_ai_o1`
- `open_ai_o1_mini`
- `open_ai_o3`
- `open_ai_o3_mini`
- `open_ai_o4_mini`

### OpenAI Responses API
```ruby
Raif.configure do |config|
  config.open_ai_models_enabled = true
  config.open_ai_api_key = ENV["OPENAI_API_KEY"]
  config.default_llm_model_key = "open_ai_responses_gpt_4o"
end
```

Currently supported OpenAI Responses API models:
- `open_ai_responses_gpt_4o_mini`
- `open_ai_responses_gpt_4o`
- `open_ai_responses_gpt_3_5_turbo`
- `open_ai_responses_gpt_4_1`
- `open_ai_responses_gpt_4_1_mini`
- `open_ai_responses_gpt_4_1_nano`
- `open_ai_responses_o1`
- `open_ai_responses_o1_mini`
- `open_ai_responses_o1_pro`
- `open_ai_responses_o3`
- `open_ai_responses_o3_mini`
- `open_ai_responses_o3_pro`
- `open_ai_responses_o4_mini`

The Responses API provides access to [provider-managed tools](#provider-managed-tools), including web search, code execution, and image generation.

## Anthropic Claude
```ruby
Raif.configure do |config|
  config.anthropic_models_enabled = true
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_llm_model_key = "anthropic_claude_3_5_sonnet"
end
```

Currently supported Anthropic models:
- `anthropic_claude_3_7_sonnet`
- `anthropic_claude_3_5_sonnet`
- `anthropic_claude_3_5_haiku`
- `anthropic_claude_3_opus`

The Anthropic adapter provides access to [provider-managed tools](#provider-managed-tools) for web search and code execution.

## AWS Bedrock (Claude)
```ruby
Raif.configure do |config|
  config.bedrock_models_enabled = true
  config.aws_bedrock_region = "us-east-1"
  config.default_llm_model_key = "bedrock_claude_3_5_sonnet"
end
```

Currently supported Bedrock models:
- `bedrock_claude_3_5_sonnet`
- `bedrock_claude_3_7_sonnet`
- `bedrock_claude_3_5_haiku`
- `bedrock_claude_3_opus`
- `bedrock_amazon_nova_micro`
- `bedrock_amazon_nova_lite`
- `bedrock_amazon_nova_pro`

Note: Raif utilizes the [AWS Bedrock gem](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/BedrockRuntime/Client.html) and AWS credentials should be configured via the AWS SDK (environment variables, IAM role, etc.)

## OpenRouter
[OpenRouter](https://openrouter.ai/) is a unified API that provides access to multiple AI models from different providers including Anthropic, Meta, Google, and more.

```ruby
Raif.configure do |config|
  config.open_router_models_enabled = true
  config.open_router_api_key = ENV["OPENROUTER_API_KEY"]
  config.open_router_app_name = "Your App Name" # Optional
  config.open_router_site_url = "https://yourdomain.com" # Optional
  config.default_llm_model_key = "open_router_claude_3_7_sonnet"
end
```

Currently included OpenRouter models:
- `open_router_claude_3_7_sonnet`
- `open_router_llama_3_3_70b_instruct`
- `open_router_llama_3_1_8b_instruct`
- `open_router_llama_4_maverick`
- `open_router_llama_4_scout`
- `open_router_gemini_2_0_flash`
- `open_router_deepseek_chat_v3`

See [Adding LLM Models](#adding-llm-models) for more information on adding new OpenRouter models.