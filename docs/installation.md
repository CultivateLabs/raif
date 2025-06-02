---
layout: default
title: Installation
nav_order: 2
---

# Installation
{: .no_toc }

This guide will walk you through installing and setting up Raif in your Rails application.
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

## Installation Steps

### 1. Add to Gemfile

Add the Raif gem to your Rails application's Gemfile:

```ruby
gem 'raif'
```

### 2. Bundle Install

Run bundle install to install the gem and its dependencies:

```bash
bundle install
```

### 3. Run the Generator

Generate the Raif configuration and migration files:

```bash
rails generate raif:install
```

This generator will:
- Create a configuration file at `config/initializers/raif.rb`
- Add database migrations for Raif's tables
- Mount the Raif engine in your routes

### 4. Run Migrations

Apply the database migrations:

```bash
rails db:migrate
```

### 5. Configure API Keys

Edit `config/initializers/raif.rb` to add your AI provider API keys:

```ruby
Raif.configure do |config|
  # OpenAI Configuration
  config.openai_api_key = ENV['OPENAI_API_KEY']
  
  # Anthropic Configuration  
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  
  # Other provider configurations...
end
```

### 6. Set Environment Variables

Add your API keys to your environment variables or Rails credentials:

```bash
# .env file
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
```

Or use Rails credentials:

```bash
rails credentials:edit
```

```yaml
openai:
  api_key: your_openai_key_here
anthropic:
  api_key: your_anthropic_key_here
```

## Verification

To verify your installation is working correctly, you can start the Rails console and test basic functionality:

```ruby
rails console

# Test that Raif is loaded
Raif.version

# Test a simple LLM call (requires API key)
Raif.llm(:gpt_4o_mini).chat(
  messages: [{ role: "user", content: "Hello, world!" }]
)
```

## Next Steps

After installation, you can:

1. [Create your first Task]({{ site.baseurl }}{% link tasks.md %})
2. Set up a Conversation (documentation coming soon)
3. Build an Agent (documentation coming soon)
4. Explore the configuration options (documentation coming soon)

## Troubleshooting

### Common Issues

**Missing API Keys**
- Ensure your API keys are properly set in environment variables or Rails credentials
- Check that the keys have the correct permissions from your AI provider

**Database Migration Errors**
- Make sure your database is running and accessible
- Check that you have the necessary permissions to create tables

**Route Mounting Issues**
- Verify that the Raif engine is properly mounted in your `config/routes.rb`
- Check for conflicts with existing routes 