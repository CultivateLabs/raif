---
layout: default
title: Installation
nav_order: 2
---

# Installation
{: .no_toc }

Install and configure Raif in your Rails application.
{: .fs-6 .fw-300 }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

- Ruby 3.0+ 
- Rails 7.0+
- PostgreSQL or MySQL database

---

## Quick Start

### 1. Add to Gemfile

```ruby
gem 'raif'
```

### 2. Install and Setup

```bash
bundle install
rails generate raif:install
rails db:migrate
```

### 3. Configure API Keys

Edit `config/initializers/raif.rb`:

```ruby
Raif.configure do |config|
  # OpenAI (recommended)
  config.open_ai_api_key = ENV['OPENAI_API_KEY']
  config.open_ai_models_enabled = true
  config.default_llm_model_key = "open_ai_gpt_4o"
  
  # Optional: Additional providers
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.anthropic_models_enabled = true
  
  config.open_router_api_key = ENV['OPENROUTER_API_KEY']
  config.open_router_models_enabled = true
end
```

### 4. Set Environment Variables

```bash
# .env file
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here  # optional
OPENROUTER_API_KEY=your_openrouter_key_here  # optional
```

---

## Verification

Test your setup in the Rails console:

```ruby
rails console

# Test configuration
Raif.config.default_llm_model_key

# Test LLM call (requires API key)
llm = Raif.llm(:open_ai_gpt_4o_mini)
completion = llm.chat(message: "Hello, world!")
puts completion.raw_response
```

---

## Next Steps

- [Create your first Task]({{ site.baseurl }}{% link tasks.md %})
- [Set up a Conversation]({{ site.baseurl }}{% link conversations.md %})
- [Build an Agent]({{ site.baseurl }}{% link agents.md %})

## Troubleshooting

**Missing API Keys**
- Ensure your API keys are set in environment variables
- Verify keys have correct permissions from your AI provider

**Database Issues**
- Check database is running and accessible
- Ensure proper table creation permissions

**Route Conflicts**
- Verify Raif engine is mounted in `config/routes.rb`
- Check for existing route conflicts 