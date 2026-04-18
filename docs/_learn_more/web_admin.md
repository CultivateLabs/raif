---
layout: default
title: Web Admin
nav_order: 1
description: "Raif's web admin interface"
---

{% include table-of-contents.md %}

# Web Admin Overview

Raif includes a web admin interface for viewing all interactions with the LLM. Assuming you have the engine mounted at `/raif`, you can access the admin interface at `/raif/admin`.

The admin interface contains sections for:
- [Model Completions](#model-completions)
- [Tasks](#tasks)
- [Conversations](#conversations)
- [Agents](#agents)
- [Model Tool Invocations](#model-tool-invocations)
- [Prompt Studio](#prompt-studio)
- [LLM Registry](#llm-registry)
- [Stats](#stats)

# Authorization

To control authorization for the admin interface, you can configure the `authorize_admin_controller_action` option in your initializer:

```ruby
Raif.configure do |config|
  config.authorize_admin_controller_action = ->{ current_user&.admin? }
end
```

# Screenshots
## Model Completions

List of `Raif::ModelCompletion` records:
![Model Completions Index](../assets/images/screenshots/admin-model-completions-index.png){:class="img-border"}

`Raif::ModelCompletion` record detail:
![Model Completion Detail](../assets/images/screenshots/admin-model-completion-show.png){:class="img-border"}

## Tasks

List of `Raif::Task` records:
![Tasks Index](../assets/images/screenshots/admin-tasks-index.png){:class="img-border"}

`Raif::Task` record detail:
![Task Detail](../assets/images/screenshots/admin-tasks-show.png){:class="img-border"}

## Conversations

List of `Raif::Conversation` records:
![Conversations Index](../assets/images/screenshots/admin-conversations-index.png){:class="img-border"}

`Raif::Conversation` record detail:
![Conversation Detail](../assets/images/screenshots/admin-conversation-show.png){:class="img-border"}

## Agents

List of `Raif::Agent` records:
![Agents Index](../assets/images/screenshots/admin-agents-index.png){:class="img-border"}

`Raif::Agent` record detail:
![Agents Detail](../assets/images/screenshots/admin-agents-show.png){:class="img-border"}

## Model Tool Invocations

List of `Raif::ModelToolInvocation` records:
![Model Tool Invocations Index](../assets/images/screenshots/admin-model-tool-invocations-index.png){:class="img-border"}

`Raif::ModelToolInvocation` record detail:
![Model Tool Invocation Detail](../assets/images/screenshots/admin-model-tool-invocation-show.png){:class="img-border"}

## Prompt Studio

Prompt Studio lets you inspect and compare [prompt templates](prompt_templates) using real database records. Select a task, conversation, or agent type, browse existing instances, and see a side-by-side comparison of the current prompt versus the prompt that was originally stored when the record was created. This makes it easy to see how template changes affect real-world inputs.

Prompt Studio is available at:
- `/raif/admin/prompt_studio/tasks`
- `/raif/admin/prompt_studio/conversations`
- `/raif/admin/prompt_studio/agents`

### Batch Runs

From Prompt Studio you can create a **batch run** that re-executes a task against a set of existing records with the current prompt and a chosen LLM, so you can see how prompt or model changes perform across many inputs. Each batch run stores its items and outputs for later inspection.

Optionally, a batch run can be scored by an **LLM judge**. Raif ships with four judge types:

- `Raif::Evals::LlmJudges::Binary` – pass/fail judgments against a criterion
- `Raif::Evals::LlmJudges::Scored` – numeric scoring against a rubric
- `Raif::Evals::LlmJudges::Comparative` – compares outputs against a reference
- `Raif::Evals::LlmJudges::Summarization` – scores summaries with a built-in rubric

See [Evals](../key_raif_concepts/evals) for more on LLM judges.

## LLM Registry

The LLM registry page at `/raif/admin/llms` lists every model registered in the running process, along with its provider, API name, and input/output token costs. Use it to verify which models are registered and to compare provider pricing when picking a default. See [Adding LLM Models](customization#adding-llm-models) to register new models.

## Stats

Stats & estimated cost tracking:
![Stats](../assets/images/screenshots/admin-stats.png){:class="img-border"}

Aggregated task stats & estimated cost tracking:
![Aggregated Task Stats](../assets/images/screenshots/admin-stats-tasks.png){:class="img-border"}

---

**Read next:** [Response Formats](response_formats)