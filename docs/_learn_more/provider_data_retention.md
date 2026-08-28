---
layout: default
title: Provider Data Retention
nav_order: 6.7
description: "Control whether an LLM provider retains the prompts Raif sends it"
---

{% include table-of-contents.md %}

# Provider Data Retention

Two providers retain prompts by default. Raif sends an explicit parameter to each one, so a host app's posture does not depend on a setting Raif cannot see.

Both settings default to the restrictive value. Both can be overridden globally, per class, or per request.

| Setting | Default | Applies to |
| --- | --- | --- |
| `open_ai_store_responses` | `false` | `Raif::Llms::OpenAiResponses` |
| `open_router_data_collection` | `"deny"` | `Raif::Llms::OpenRouter` |

## OpenAI Responses API

The Responses API defaults `store` to `true`. OpenAI then retains the request, and the prompt is readable in the organization's dashboard and logs. Raif sends `store: false` instead.

```ruby
Raif.configure do |config|
  # Set to true for dashboard visibility and provider-side response retrieval.
  config.open_ai_store_responses = false
end
```

The Chat Completions API already defaults `store` to `false`, so `Raif::Llms::OpenAiCompletions` sends nothing and this setting does not apply to it.

## OpenRouter

OpenRouter routes each request to an upstream inference provider. Some of those providers log prompts and train on them. Without an explicit preference, the routing falls back to the account-level privacy setting on openrouter.ai, which the host app cannot read from its own code.

Raif sends `provider: { data_collection: "deny" }`, which restricts routing to providers that do not store prompts. `"allow"` permits any provider.

```ruby
Raif.configure do |config|
  config.open_router_data_collection = "deny"
end
```

Note that `"deny"` narrows the set of endpoints OpenRouter will route to. A model whose only endpoints collect data returns a no-endpoints error rather than a completion. Confirm the account-level setting on openrouter.ai separately, so the guarantee does not rest on one of the two alone.

## Overriding a setting

A `Raif::Task`, `Raif::Conversation` or `Raif::Agent` subclass can override either setting for every request it makes:

```ruby
class Raif::Tasks::PublicSummary < Raif::Task
  self.open_ai_store_responses = true

  def build_prompt
    "Summarize the following press release: ..."
  end
end
```

`Raif::Llm#chat` takes the same two keywords for a one-off override:

```ruby
Raif.llm(:open_ai_responses_gpt_4o).chat(
  message: "Summarize the following press release: ...",
  open_ai_store_responses: true
)
```

An override is persisted on the `Raif::ModelCompletion`, in its `request_settings` jsonb column. An absent key means "use the `Raif.config` value", so only a deliberate override is recorded. `Raif::ModelCompletion::REQUEST_SETTING_KEYS` lists every key the column may carry, and both keys and values are validated.

Persisting matters for batch inference: submission reloads its completions from the database, in a later process, and builds the provider request from what it finds there.
