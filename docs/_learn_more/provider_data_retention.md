---
layout: default
title: Provider Data Retention
nav_order: 6.7
description: "Control whether an LLM provider retains the prompts Raif sends it"
---

{% include table-of-contents.md %}

# Provider Data Retention

Two providers store the prompts they are sent by default. Raif sends an explicit parameter to each one, so a host app's posture does not depend on a setting Raif cannot see.

Each setting can be overridden globally, per class, or per request.

| Setting | Default | Sends | Applies to |
| --- | --- | --- | --- |
| `open_ai_store_responses` | `false` | `store` | `Raif::Llms::OpenAiResponses` |
| `open_router_data_collection` | `"deny"` | `provider.data_collection` | `Raif::Llms::OpenRouter` |
| `open_router_zdr` | `false` | `provider.zdr` | `Raif::Llms::OpenRouter` |

Neither provider's parameter amounts to zero retention on its own. Read the caveat in each section below before you treat one as a guarantee.

## OpenAI Responses API

The Responses API defaults `store` to `true`. OpenAI then keeps the response object for 30 days, where the prompt is readable in the organization's dashboard and retrievable by response id. Raif sends `store: false` instead.

```ruby
Raif.configure do |config|
  # Set to true for dashboard visibility and provider-side response retrieval.
  config.open_ai_store_responses = false
end
```

The Chat Completions API already defaults `store` to `false`, so `Raif::Llms::OpenAiCompletions` sends nothing and this setting does not apply to it.

`store: false` is not zero retention. OpenAI generates abuse monitoring logs for all API usage and holds them for up to 30 days, whatever `store` says. Only an organization approved for Zero Data Retention or Modified Abuse Monitoring escapes that, and under Zero Data Retention OpenAI treats `store` as `false` regardless of what the request asks for - so setting this to `true` there has no effect.

## OpenRouter

OpenRouter routes each request to an upstream inference provider. Some of those providers store prompts non-transiently and train on them. OpenRouter defaults `data_collection` to `"allow"`, which filters nothing, so without an explicit preference the only thing narrowing the routing is the account-level privacy setting on openrouter.ai, which the host app cannot read from its own code.

Raif sends `provider: { data_collection: "deny" }`, which routes only to providers that do not collect user data.

```ruby
Raif.configure do |config|
  config.open_router_data_collection = "deny"
end
```

`"deny"` narrows the set of endpoints OpenRouter will route to. A model whose only endpoints collect data returns a no-endpoints error rather than a completion.

`"allow"` cannot widen the routing past the account-level setting. Request preferences narrow within it rather than override it, so an account that denies data collection stays denied whatever a request asks for. Set the account-level setting to match your intent as well.

### Zero data retention

`data_collection` is about training and non-transient storage, not retention. OpenRouter states it has no routing rules based on providers' data retention policies, so a provider that holds prompts for a fixed window without training on them still satisfies `"deny"`.

`provider: { zdr: true }` is the control that restricts routing to endpoints with a Zero Data Retention policy. Raif sends it only when `open_router_zdr` is true:

```ruby
Raif.configure do |config|
  config.open_router_zdr = true
end
```

It defaults to `false` because it is a far narrower filter than `data_collection`. Many models have no ZDR endpoint at all and will return a no-endpoints error once it is on. Check the models you use before enabling it.

The parameter is omitted rather than sent as `false`, since OpenRouter treats `false` and absent alike. A per-request `zdr` is OR'd with the account-wide and guardrail ZDR settings, so it can only add enforcement, never remove it.

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

`Raif::Llm#chat` takes the same three keywords for a one-off override:

```ruby
Raif.llm(:open_ai_responses_gpt_4o).chat(
  message: "Summarize the following press release: ...",
  open_ai_store_responses: true
)
```

An override is persisted on the `Raif::ModelCompletion`, in its `request_settings` jsonb column. An absent key means "use the `Raif.config` value", so only a deliberate override is recorded. `Raif::ModelCompletion::REQUEST_SETTING_KEYS` lists every key the column may carry, and both keys and values are validated.

Persisting matters for batch inference: submission reloads its completions from the database, in a later process, and builds the provider request from what it finds there.
