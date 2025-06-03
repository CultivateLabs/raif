---
layout: default
title: Home
nav_order: 1
description: "Raif (Ruby AI Framework) - A Rails engine for adding AI-powered features to Rails applications"
permalink: /
---

# Raif - Ruby AI Framework
{: .fs-9 }

A Rails engine that helps developers add AI-powered features to Rails applications with ease.
{: .fs-6 .fw-300 }

[Get started now](#getting-started){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View it on GitHub](https://github.com/CultivateLabs/raif){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Getting Started

Raif is a Ruby AI Framework built as a Rails engine that provides:

- **Tasks** - Single-shot AI operations with defined prompts and response formats
- **Conversations** - Multi-turn chat interfaces with LLMs  
- **Agents** - ReAct-style agents that can use tools in loops
- **Model Tools** - Custom tools that agents/conversations can invoke
- **Multiple LLM Providers** - OpenAI, Anthropic Claude, AWS Bedrock, OpenRouter

### Quick Start

Add Raif to your Rails application:

```ruby
# Gemfile
gem 'raif'
```

```bash
bundle install
rails generate raif:install
```

### Key Features

- **Multiple AI Providers**: Support for OpenAI, Anthropic, AWS Bedrock, and more
- **Flexible Response Formats**: HTML, JSON, and text responses
- **Tool Integration**: Custom tools and provider-managed tools (web search, code execution)
- **Conversation Management**: Multi-turn conversations with context preservation  
- **Agent Framework**: ReAct-style agents with tool use capabilities
- **Rails Integration**: Seamless integration with existing Rails applications

### Architecture Overview

Raif follows a modular architecture with clear separation of concerns:

- **Core Components** handle the main AI operations
- **LLM Adapters** provide unified interfaces to different AI providers
- **Database Models** store conversations, completions, and tool invocations
- **Generators** help scaffold new AI components quickly

---

## About the Project

Raif is developed to make AI integration in Rails applications straightforward and powerful. It abstracts away the complexity of working with different LLM providers while providing a consistent, Rails-friendly interface.

### Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/CultivateLabs/raif](https://github.com/CultivateLabs/raif).

### License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT). 