# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Raif (Ruby AI Framework) is a Rails engine that provides AI-powered features for Rails applications. It supports multiple LLM providers (OpenAI, Anthropic Claude, AWS Bedrock, OpenRouter) and implements tasks, conversations, and ReAct-style agents with tool capabilities.

## Development Commands

### Initial Setup
```bash
bundle install
yarn install
bin/rails app:db:create
bin/rails app:db:migrate
```

### Running Tests
```bash
bundle exec rspec              # Run all tests
bundle exec guard              # Auto-reload test runner
```

### Building Assets
```bash
yarn build:css                 # Build CSS
yarn watch:css                 # Watch and rebuild CSS
```

### Linting
```bash
bin/lint                       # Run all linters
bin/lint -a                    # Run with auto-fix
```

### Development Server
```bash
bin/rails server               # Run dummy app server
```

### Documentation
```bash
bundle exec rake yard          # Generate YARD docs
```

## Architecture & Key Patterns

### Core Domain Model
- **Raif::Llm**: Base class for LLM providers with unified interface
- **Raif::Conversation**: Main aggregate for chat interactions, supports polymorphic types
- **Raif::Agent**: Autonomous agents with NativeToolCalling and ReAct implementations
- **Raif::ModelTool**: AI-callable tools with JSON Schema validation

### Registry Pattern
```ruby
# Providers are registered dynamically
Raif.register_llm(Raif::Llms::Anthropic, key: :anthropic_claude_3_5_sonnet, ...)
Raif.llm(:anthropic_claude_3_5_sonnet)  # Returns configured instance
```

### Key Design Patterns
- **Isolated namespace**: All models/controllers under `Raif::`
- **Concern-based composition**: HasLlm, InvokesModelTools, LlmResponseParsing
- **STI (Single Table Inheritance)**: For conversations, agents, tools
- **Polymorphic associations**: For creator relationships
- **Streaming by default**: Uses SSE and Turbo Streams for real-time updates

### Testing Patterns
- Uses RSpec with FactoryBot
- VCR for recording LLM API interactions
- Test helpers: `stubbed_llm`, `stub_raif_task`, `stub_raif_conversation`, `stub_raif_agent`
- Shortcut: `FB = FactoryBot`

## Important Development Practices

1. **API Keys**: Set via environment variables (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.)
2. **Migrations**: Run `rails raif:install:migrations` to copy engine migrations
3. **View Customization**: Use `rails g raif:views` to override engine views
4. **Factory Access**: Host apps automatically get Raif's factories via FactoryBot

## Generators

```bash
rails g raif:install           # Create initializer
rails g raif:agent AgentName   # Create agent class
rails g raif:conversation ConversationTypeName  # Create conversation class
rails g raif:task TaskName --response-format html|text|json  # Create task
rails g raif:model_tool ToolName  # Create model tool
rails g raif:views             # Copy views for customization
```

## Common Pitfalls

- AWS Bedrock requires `aws-sdk-bedrockruntime` gem and AWS credentials
- Migration checker warns in development if Raif migrations are missing
- Provider configuration validates that default model keys match registered models
- Test environment automatically registers test LLMs and embedding models

## File Structure

- `app/` - Rails engine application code (controllers, models, views, jobs)
- `lib/raif/` - Core framework code, registries, configuration
- `lib/generators/` - Rails generators
- `spec/` - RSpec tests with dummy Rails app
- `docs/` - Jekyll documentation site
- `vcr_cassettes/` - Recorded API interactions for tests