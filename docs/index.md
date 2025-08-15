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

[Get started now](getting_started/setup){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View it on GitHub](https://github.com/CultivateLabs/raif){:target="_blank"}{: .btn .fs-5 .mb-4 .mb-md-0 }

---

## Overview

Raif is a Ruby on Rails engine for adding AI-powered features to Rails applications. This allows Raif to provide a full MVC stack for working with LLMs.

### Key Features
- **[Tasks](key_raif_concepts/tasks)** - Single-shot AI operations for organizing LLM prompts
- **[Conversations](key_raif_concepts/conversations)** - Full-stack LLM chat interfaces, including multi-turn chat history preservation and streaming support.
- **[Agents](key_raif_concepts/agents)** - ReAct-style agents that can use tools in loops
- **[Custom Model Tools](key_raif_concepts/model_tools)** - Custom tools that tasks/conversations/agents can invoke to interact with external systems
- **[Evals](key_raif_concepts/evals)** - Evaluate the performance of your LLM-powered features
- **[Provider-Managed Tools](key_raif_concepts/model_tools#provider-managed-tools)** - Support for tools that are managed by the LLM provider, such as web search, code execution, and image generation.
- **[Multiple LLM Providers Adapters](getting_started/setup#configuring-llm-providers--api-keys)** - OpenAI, Anthropic Claude, AWS Bedrock, OpenRouter
- **[Built-in Response Format Handling](learn_more/response_formats)** - Support for structured outputs including JSON responses, schemas, & parsing. HTML response handling and sanitization.
- **[Image & PDF Support](learn_more/images_files_pdfs)** - Support for including images and PDF in prompts.
- **[Web Admin Interface](learn_more/web_admin)** - A web interface for viewing and managing all LLM interactions.

---

## About the Project

Raif and its core concepts were extracted from [ARC Analysis](https://www.arcanalysis.ai?utm_source=raif-docs){:target="_blank"}, an AI-driven research & analysis platform built by [Cultivate Labs](https://www.cultivatelabs.com?utm_source=raif-docs){:target="_blank"}.

### Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/CultivateLabs/raif](https://github.com/CultivateLabs/raif?utm_source=raif-docs){:target="_blank"}.

### License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT){:target="_blank"}. 

