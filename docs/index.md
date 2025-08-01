---
layout: default
title: Home
nav_order: 1
description: "Raif (Ruby AI Framework) - A Rails engine for adding AI-powered features to Rails applications"
permalink: /
nav_exclude: true
---

<div style="text-align: center; margin-bottom: 2rem;">
  <img src="{{ site.baseurl }}/assets/images/raif-logo.svg" alt="Raif Logo" style="height: 120px; width: auto;">
</div>

# Raif - a Ruby AI Framework
{: .fs-9 }

A Rails engine for adding AI-powered features to Rails applications.
{: .fs-6 .fw-300 }

[Get started now](setup){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View it on GitHub](https://github.com/CultivateLabs/raif){:target="_blank"}{: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Overview

Raif is a Ruby on Rails engine for adding AI-powered features to Rails applications. This allows Raif to provide a full MVC stack for AI-powered features. 

### Key Features
- **Tasks** - Single-shot AI operations for organizing LLM prompts
- **Conversations** - Full-stack LLM chat interfaces, including multi-turn context preservation and streaming support.
- **Agents** - ReAct-style agents that can use tools in loops
- **Custom Model Tools** - Custom tools that agents/conversations can invoke to interact with external systems
- **Provider-Managed Tools** - Support for [provider-managed tools](key_raif_concepts/model_tools#provider-managed-tools) that are managed by the LLM provider, such as web search, code execution, and image generation.
- **Multiple LLM Providers Adapters** - OpenAI, Anthropic Claude, AWS Bedrock, OpenRouter
- **Built-in Response Format Handling** - Support for structured outputs including JSON responses, schemas, & parsing. HTML response handling and sanitization.
- **Image & PDF Support** - Support for including images and PDF in prompts.
- **Web Admin Interface** - A web interface for viewing and managing all LLM interactions.

---

## About the Project

Raif and its core concepts were extracted from [ARC Analysis](https://www.arcanalysis.ai){:target="_blank"}, an AI-driven research & analysis platform built by [Cultivate Labs](https://www.cultivatelabs.com){:target="_blank"}.

### Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/CultivateLabs/raif](https://github.com/CultivateLabs/raif){:target="_blank"}.

### License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT){:target="_blank"}. 

