---
layout: default
title: Task Batching
nav_order: 3.5
description: "Submit many tasks through a provider Batch API in exchange for a ~50% discount"
---

{% include table-of-contents.md %}

# Task Batching

Anthropic and OpenAI both expose a Batch API: you submit a JSONL of requests, the provider processes them asynchronously (typically minutes, with a 24-hour ceiling), and you fetch results in one go in exchange for ~50% off the per-token rate. Raif wraps both behind a single `Raif::ModelCompletionBatch` primitive so your task code doesn't have to care which provider it's talking to.

## Provider support

| Provider     | Batch support |
|--------------|---------------|
| Anthropic    | Yes (Messages Batches API) |
| OpenAI       | Yes (Batch API, Completions and Responses) |
| Bedrock      | No |
| Google       | No |
| OpenRouter   | No |

Guard with `Raif.llm(model_key).supports_batch_inference?` if you need to fall back to `Raif::Task.run` for non-batch-capable providers.

# Producing a batch

Three steps: ask the LLM for a batch, build your tasks, attach them.

```ruby
llm = Raif.llm(:anthropic_claude_4_6_sonnet)

batch = llm.create_batch(
  completion_handler_class_name: "MyApp::DocumentSummaryBatchHandler",
  metadata: {
    "campaign_id" => campaign.id,
    "requested_by_user_id" => current_user.id
  }
)

documents.each do |document|
  task = Raif::Tasks::DocumentSummarization.new(
    creator: current_user,
    document: document
  )
  batch.add_task(task, batch_custom_id: "doc_#{document.id}")
end

batch.submit!
```

`batch.add_task(task, batch_custom_id: ...)` saves the task if it isn't already and routes it through `Raif::Task#prepare_for_batch!` to build the pending `Raif::ModelCompletion` attached to the batch. No LLM request is made until `batch.submit!`.

A few details worth knowing:

- **`batch_custom_id`** must be unique within a single batch. It's the identifier the provider echoes back on each per-entry result so Raif can match it to the right child completion. Raif enforces a unique partial index on `(raif_model_completion_batch_id, batch_custom_id)`. Defaults to `"raif_task_<task.id>"` if you don't pass one explicitly – pass your own when the task ID alone isn't meaningful for debugging.
- **`metadata`** is a `json` column. Use it to carry whatever context your completion handler needs to resolve domain records (account, workflow, campaign, etc.). It is not sent to the provider.
- **`completion_handler_class_name`** is the class that runs once the batch reaches a terminal state. See [Consuming a batch](#consuming-a-batch).

`batch.submit!` is single-shot – it serializes every child completion into the provider's batch payload, uploads/creates the batch, stamps `provider_batch_id` and `submitted_at`, and auto-enqueues `Raif::PollModelCompletionBatchJob`. A second call on the same batch raises `Raif::Errors::InvalidBatchError`. If you need to retry, cancel and create a new batch.

## One-call shortcut

If you don't need a separate handle on the task before attaching it, `Raif::Task.build_for_batch` collapses construction + save + attachment into a single call:

```ruby
documents.each do |document|
  Raif::Tasks::DocumentSummarization.build_for_batch(
    batch: batch,
    batch_custom_id: "doc_#{document.id}",
    creator: current_user,
    document: document
  )
end
```

Equivalent to the `new` + `add_task` pair above; reach for it when the loop body is the entire task lifecycle.

# The polling lifecycle

You don't usually interact with the polling job directly. Once `submit!` is called:

1. `Raif::PollModelCompletionBatchJob` is enqueued with a delay from `Raif.config.model_completion_batch_poll_schedule` (default: `[1m, 2m, 5m, 10m, 30m]`, repeating the last entry).
2. Each poll calls `batch.fetch_status!`. Transient provider errors (the classes in `Raif.config.llm_request_retriable_exceptions`) cause the chain to self-reschedule rather than fail the job.
3. When the batch hits a terminal status:
   - **`ended`** (success): `batch.fetch_results!` streams the per-entry payload back from the provider. Each child completion is updated in place via `apply_batch_result` (token usage, costs, raw response, completed/failed transition).
   - **`canceled` / `expired` / `failed`**: every still-pending child is force-failed with the batch status as the reason. No per-entry fetch happens.
4. `batch.dispatch_completion_handler!` runs your handler.

If a batch outlives `Raif.config.model_completion_batch_max_age` (default 26 hours) without resolving, it's expired: raif issues a best-effort provider-side cancel via `batch.cancel!` and then force-fails the batch locally so any waiting workflow can advance. If the cancel call fails (network, 5xx, etc.), the local force-fail still happens — the provider-side batch may continue running and be billed, but raif logs and moves on. The hourly safety sweep `Raif::ExpireStuckModelCompletionBatchesJob` runs the same expiry path for batches whose polling chain was dropped entirely (e.g., a queue restart that loses scheduled jobs). **Schedule it to run hourly in your host app's cron** – without it, a stranded batch never advances.

```yaml
# config/schedule.yml (sidekiq-cron example)
expire_stuck_model_completion_batches:
  cron: "every hour"
  class: "Raif::ExpireStuckModelCompletionBatchesJob"
  queue: "default"
```

# Consuming a batch

Subclass `Raif::TaskBatchCompletionHandler` and register a completion block. Inside the block, `batch` and `tasks` are exposed as readers.

```ruby
class MyApp::DocumentSummaryBatchHandler < Raif::TaskBatchCompletionHandler
  on_batch_completion do
    campaign = Campaign.find_by(id: batch.metadata["campaign_id"])
    next unless campaign

    successful = tasks.select(&:completed?)
    failed = tasks.reject(&:completed?)

    successful.each do |task|
      campaign.summaries.create!(
        document_id: task.run_with["document"].id,
        text: task.parsed_response["summary"]
      )
    end

    Airbrake.notify("Document summary batch had #{failed.size} failures") if failed.any?
  end
end
```

Things to know about the handler:

- The base class hydrates each child `Raif::ModelCompletion` through its source `Raif::Task#process_completion!` *before* your block runs. By the time the block executes, every task is in its terminal state (`completed?` or `failed?`), `parsed_response` is populated, and any model tool invocations have been processed. You filter, you don't transition.
- The block is `instance_exec`'d on a handler instance, so any helper methods you define on the subclass are callable directly:

  ```ruby
  class MyApp::DocumentSummaryBatchHandler < Raif::TaskBatchCompletionHandler
    on_batch_completion do
      next if successful_tasks.empty?
      persist!(successful_tasks)
    end

    def successful_tasks
      tasks.select(&:completed?)
    end

    def persist!(completed_tasks)
      # ...
    end
  end
  ```

- Use `next` (not `return`) for early exit. The block is defined at class-body scope, so `return` would raise `LocalJumpError`.
- Per-task hydration errors are caught and logged so one bad task doesn't block the rest of the batch. Errors raised from inside your `on_batch_completion` block propagate to `Raif::PollModelCompletionBatchJob` – handle them yourself if you need different semantics.
- The handler runs for whole-batch failures too. Check `batch.successful?` (true only when `status == "ended"`) before assuming you have results to aggregate. `batch.failure_reason` carries the provider-side detail when available.

If you're attaching non-task completions to a batch via `Raif::Llm#build_pending_model_completion` directly, override `handle_batch_completion(batch)` instead of using `on_batch_completion` – you'll skip the task hydration step and read children off `batch.raif_model_completions`.

# Cancellation

Cancellation is provider-side and asynchronous on both Anthropic and OpenAI: the request is acknowledged with a transitional status, and the next poll picks up the final `canceled` state. Force-failing remaining children and dispatching the handler happens through the same path as any other terminal status, so the handler always runs once.

```ruby
batch.cancel!
```

Refuses to cancel a batch that's already terminal or hasn't been submitted yet (no `provider_batch_id`).

# Configuration

```ruby
Raif.configure do |config|
  # Backoff between polls of a non-terminal batch. The Nth poll waits
  # poll_schedule[N], clamping to the last entry once exhausted.
  config.model_completion_batch_poll_schedule = [
    60.seconds,
    2.minutes,
    5.minutes,
    10.minutes,
    30.minutes
  ]

  # Hard ceiling on any non-terminal batch. The hourly safety sweep
  # force-fails older batches so the workflow can advance.
  config.model_completion_batch_max_age = 26.hours

  # OpenAI-only: the completion_window passed when creating an OpenAI batch.
  # OpenAI currently only accepts "24h".
  config.open_ai_batch_completion_window = "24h"

  # Anthropic-only: beta header for the Messages Batches API.
  config.anthropic_message_batches_beta_header = "message-batches-2024-09-24"
end
```

# Schema and accessors

```ruby
batch.status                # one of: pending, submitted, in_progress, ended, canceled, expired, failed
batch.terminal?             # true once status is ended/canceled/expired/failed
batch.successful?           # true only when status == "ended"
batch.provider_batch_id     # the provider's id for the batch
batch.submitted_at
batch.ended_at
batch.failure_error
batch.failure_reason
batch.request_counts        # provider-reported per-status counts (jsonb)
batch.metadata              # whatever you put on it (jsonb)
batch.raif_model_completions
batch.tasks                 # convenience: Raif::Task records attached via their child completions
batch.total_cost            # aggregated after results are applied
batch.prompt_token_cost
batch.output_token_cost
```

Costs reflect the provider's batch discount – `apply_batch_result` halves the per-token rate before persisting it on each child completion, and `recalculate_costs!` rolls the children up to the batch.

# Testing

The synchronous path of a task is exercised by `Raif::Task.run`. The batch path can be exercised by building a batch + children with `Task.build_for_batch`, populating each child completion's `raw_response` directly, marking it `completed!` (or `failed!`), and then calling `YourHandler.handle_batch_completion(batch)`. The handler's hydration step will route each child through `Raif::Task#process_completion!` exactly as the polling job would, so the resulting tasks (and any side records your handler creates) match production output.

---

**Read next:** [Images/Files/PDFs](images_files_pdfs)
