---
layout: default
title: Prompt Templates
nav_order: 1.5
description: "Define prompts using ERB templates with Rails view helpers, partials, and preview support"
---

{% include table-of-contents.md %}

# Prompt Templates

Raif supports defining prompts in ERB template files, similar to how Rails controllers render views. This provides a clean separation between prompt content and Ruby logic, and gives you access to Rails view helpers and partials.

# Template Location Convention

Templates are located based on the class name:

```
Raif::Tasks::SummarizeDocument → app/views/raif/tasks/summarize_document.prompt.erb
Raif::Tasks::Docs::Summarize → app/views/raif/tasks/docs/summarize.prompt.erb
Raif::Agents::ResearchAgent → app/views/raif/agents/research_agent.system_prompt.erb
Raif::Conversations::HelpChat → app/views/raif/conversations/help_chat.system_prompt.erb
```

Two template types are supported:
- `.prompt.erb` — The main LLM prompt (for tasks)
- `.system_prompt.erb` — System prompt override (for tasks, conversations, agents)

# Basic Usage

Generate a task:

```bash
rails generate raif:task SummarizeDocument --response-format html
```

This creates both the task class and a prompt template:

```ruby
# app/models/raif/tasks/summarize_document.rb
class Raif::Tasks::SummarizeDocument < Raif::ApplicationTask
  llm_response_format :html

  run_with :document
  run_with :max_sentences

  def formatted_content
    document.content.strip
  end

  # Prompt is defined in app/views/raif/tasks/summarize_document.prompt.erb
end
```

{% raw %}
```erb
<% # app/views/raif/tasks/summarize_document.prompt.erb %>

<%= content_tag(:document, formatted_content) %>

Please summarize the document above in <%= max_sentences %> sentences or fewer.

Format your response using basic HTML tags.
```
{% endraw %}

Run the task as usual:

```ruby
task = Raif::Tasks::SummarizeDocument.run(
  document: document,
  max_sentences: 3,
  creator: current_user
)
```

# Template Context

Templates have access to:
- **All instance methods** defined on the task/conversation/agent
- **All `run_with` attributes**
- **Rails view helpers** such as `content_tag`, `strip_tags`, `truncate`, `number_to_human`, etc.
- **Partials** via `render partial: '...'`

{% raw %}
```erb
<%= content_tag(:context, background_info) %>

<%= truncate(long_text, length: 500) %>

<%= render partial: "raif/shared/standard_instructions" %>
```
{% endraw %}

# Partials

Templates support Rails partials, enabling reusable prompt fragments across tasks:

{% raw %}
```erb
<% # app/views/raif/shared/_json_instructions.prompt.erb %>
Format your response as valid JSON. Do not include any text outside the JSON object.
```
{% endraw %}

{% raw %}
```erb
<% # app/views/raif/tasks/extract_data.prompt.erb %>
Extract the key data points from the following text:

<%= content_tag(:text, document_text) %>

<%= render partial: "raif/shared/json_instructions" %>
```
{% endraw %}

# System Prompt Templates

You can define a system prompt template for any task, conversation, or agent:

{% raw %}
```erb
<% # app/views/raif/tasks/summarize_document.system_prompt.erb %>
You are an expert at summarizing documents clearly and concisely.
<%- if requested_language_key.present? %>
<%= system_prompt_language_preference %>
<%- end %>
```
{% endraw %}

When no `.system_prompt.erb` template exists, the default system prompt behavior is preserved (using `Raif.config.task_system_prompt_intro` for tasks, `Raif.config.conversation_system_prompt_intro` for conversations, etc.).

# Precedence Rules

For prompts:
1. If a `.prompt.erb` template file exists, use it
2. If no template but the subclass overrides `build_prompt`, use the method
3. If neither exists, raise `NotImplementedError`

For system prompts:
1. If a `.system_prompt.erb` template exists, use it
2. Otherwise, use the default system prompt behavior

This means you can mix and match — use a template for the prompt but override `build_system_prompt` in Ruby, or vice versa.

# Skipping Template Generation

If you prefer the method-based approach, pass `--skip-prompt-template` to the generator:

```bash
rails generate raif:task MyTask --skip-prompt-template
```

# Error Handling

If a template has a rendering error, Raif wraps it in a `Raif::Errors::PromptTemplateError` that includes the template path and original error, making debugging straightforward:

```
Raif::Errors::PromptTemplateError: Error rendering prompt template
  'raif/tasks/summarize_document.prompt.erb': ActionView::Template::Error: undefined method 'foo'
```

---

**Read next:** [Response Formats](response_formats)
