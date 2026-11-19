---
layout: default
title: Durable Agent Runs
nav_order: 3.6
description: "Run agents in background jobs, run tool calls in parallel, and wait for slow tools without holding a worker"
---

{% include table-of-contents.md %}

# Durable Agent Runs

An agent run is a persisted state machine. Each turn of the run is a `Raif::AgentTurn` row that records how far the turn got: the model completion was requested, the completion was saved, the tool calls were dispatched, the tool calls are complete. Every step reads the saved state first, so a step that runs a second time (after a deploy, a crashed worker, or a duplicate job delivery) continues from where the run stopped. It does not repeat a model call or a tool call that already happened.

There is one implementation and two ways to drive it:

| | `agent.run_later!` | `agent.run!` |
|---|---|---|
| Runs in | Background jobs: one per turn, one per tool call | The calling process |
| Returns | Immediately, with the agent | When the run ends, with the final answer |
| Tool calls of one turn | In parallel, across workers | One after the other |
| Tools with [deferred completion](#deferred-completion) | Supported | Raises `Raif::Errors::AgentRunError` |
| Use it for | Production runs | Specs, the console, callers that need the answer before they continue |

```ruby
agent = Raif::Agents::NativeToolCallingAgent.new(
  task: "What is Jimmy Buffet's birthday?",
  available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
  creator: current_user
)

agent.run_later!
agent.status # => :running
```

`agent.status` returns `:pending`, `:running`, `:waiting`, `:completed`, `:failed`, or `:canceled`. An agent is `:waiting` while a turn's tool calls have not all ended; `agent.pending_tool_invocations` lists them. Waiting uses no iterations and makes no model calls.

A run can only be started once. `agent.cancel!` stops a run: queued and running jobs for it do nothing more, and results that arrive later are ignored.

# How a turn runs

1. `Raif::AgentTurnJob` requests the model completion and saves it on the turn.
2. It validates the tool calls in the completion and creates one `Raif::ModelToolInvocation` per call. The job then ends.
3. Each tool call runs in its own `Raif::ModelToolInvocationJob`. A turn with a single call runs it in the turn job instead, because a job of its own would only add queue delay.
4. When an invocation ends, it checks the turn's barrier under a row lock. When no unfinished invocation is left, exactly one caller opens the barrier: it writes the tool calls and their results to the conversation history **in call order**, whatever order they ended in, and queues the next turn.

Raif does not use threads for this and does not depend on any queue backend's batch feature. Any ActiveJob adapter works.

## Queues

Every turn adds one queue delay and every tool job adds another, so put them on a queue with spare capacity:

```ruby
Raif.configure do |config|
  config.agent_turn_job_queue = :agents
  config.model_tool_invocation_job_queue = :agent_tools
end

# or per agent class
class ResearchAgent < Raif::ApplicationAgent
  self.turn_job_queue = :research
  self.tool_invocation_job_queue = :research_tools
end
```

# Deferred completion {#deferred-completion}

Some tools cannot produce their result before `process_invocation` returns: the result comes from slow background work, a long-running export, or a callback from another system. Declare that the tool defers completion. Its job starts the work and returns. The invocation stays unfinished, and the agent waits, until your code completes it.

```ruby
class SlowLookup < Raif::ModelTool
  defers_completion deadline: 45.minutes

  def self.process_invocation(invocation)
    SlowLookupJob.perform_later(invocation)
  end
end

# Later, wherever the work finishes:
invocation.complete!(rows: rows)
# or, when it cannot produce a result:
invocation.fail!("The source returned no data for that query.")
```

- `complete!(result)` stores the result. `fail!(message)` sends `message` to the model as the error result of the call, so write it for the model. In both cases the run continues once every invocation of the turn has ended.
- Both return `false` and change nothing when the invocation has already ended, for example because its deadline passed. A late callback is harmless.
- Pass the result to `complete!` rather than saving it on the invocation in the same transaction. On MySQL, a transaction that writes or locks the invocation and then calls `complete!` or `fail!` can deadlock with the caller that ends another call of the same turn. On Postgres, Raif assumes the default READ COMMITTED isolation level.
- `process_invocation` can run a second time if its job is retried before it returns. Start the work idempotently; `invocation.id` is a stable key.

## Deadlines

Every invocation that runs in a job has a deadline. When it passes, the model gets an error result for that call and the run continues. The run does not fail.

| Setting | Default | Applies to |
|---|---|---|
| `config.model_tool_invocation_deadline` | `10.minutes` | Tool calls that complete when the tool returns |
| `config.deferred_model_tool_invocation_deadline` | `30.minutes` | Tools that declare `defers_completion` |

A tool class can set its own with `defers_completion deadline: 2.hours` or `invocation_deadline 2.minutes`, and `invocation.extend_deadline!(time)` moves the deadline of one invocation.

A deadline stops the wait. It does not stop tool code or host work that is still running, and a result that arrives after the deadline is ignored.

# Tool errors

The rules of `recover_from_tool_errors` apply in jobs as they do in `run!`: an exception raised by a tool becomes an error result for the model, and the run continues. An error that `recoverable_tool_error?` rejects fails the run. Calls of the same turn that have not started are canceled. A call that is already running finishes, and its result is saved, but it does not advance the run.

# Tool execution guarantee

Raif runs a tool **at most once** per invocation. If a worker stops while a tool runs, Raif does not run the tool again, because it cannot know whether the first execution already had an effect outside the database. The invocation ends at its deadline with an error result, and the model can make the call again.

A tool whose second execution is harmless (a read, or a write keyed on `invocation.id`) can opt in to being run again:

```ruby
class WikipediaSearch < Raif::ModelTool
  retry_safe lease: 2.minutes
end
```

A later execution then takes the invocation over once `lease` has passed since the first one started. The lease must be longer than the tool can run.

# Restoring host context {#restoring-host-context}

Jobs run outside the request that started the run, so per-request state (current-attributes objects, a permission scope, a tenant) is gone when tool code runs. Override `with_run_context` to set it again. Raif calls it around every turn job, every tool job, and the continuation that a deadline or a `complete!` call starts.

```ruby
class ResearchAgent < Raif::ApplicationAgent
  def with_run_context
    Current.set(account: source.account, user: creator) { yield }
  end
end
```

# Progress

A block cannot travel between jobs, so `run_later!` reports progress through methods you override on the agent class:

```ruby
class ResearchAgent < Raif::ApplicationAgent
  def after_conversation_history_entry(entry)
    Turbo::StreamsChannel.broadcast_append_to(self, target: "agent-progress", partial: "agents/entry", locals: { entry: entry })
  end

  def after_tool_calls_dispatched(turn)
    # the calls of this turn were created and are about to run
  end

  def after_turn(turn); end

  def after_run
    # completed, failed, or canceled: check `status`
  end
end
```

The entries of one turn are added together when the turn's barrier opens, so a tool call entry arrives with its result. Use `after_tool_calls_dispatched` to show calls when they start. `after_turn` and `after_run` can run more than once after a crash, so keep them idempotent.

The block form of `run!` still works and receives the same entries.

# Recovery

Every step of a run is queued by the step before it. If the queue backend loses a job, the run would stop. Schedule `Raif::RecoverStalledRunsJob` every few minutes with your queue adapter's recurring-job mechanism:

```ruby
Raif::RecoverStalledRunsJob.perform_later
```

It expires invocations whose deadline passed, resumes async runs whose current turn has not changed for `config.agent_stalled_turn_resume_after` (default `30.minutes`, `nil` to disable), and finishes [conversation entries](../key_raif_concepts/conversations#tool-jobs) whose tool calls ended without their continuation running. Everything it does is safe to repeat. You can also call `agent.resume!` yourself at any time.

Keep `agent_stalled_turn_resume_after` well above your slowest model call. Resuming a turn whose model call is still in flight pays for a second call.

## What a crash costs

| The process stops... | Recovery |
|---|---|
| before the model response is saved | The model is called again. This is the one case that pays twice. |
| after the response is saved, before the turn records it | The saved completion is attached. No model call. |
| after the tool calls are created, before their jobs are queued | The jobs are queued again. |
| while a tool runs | The invocation ends at its deadline, or a `retry_safe` tool is run again. |
| after the last tool call ended, before the next turn is queued | The continuation runs. |

# Prompt cache cost of waiting

Provider prompt caches expire after a few minutes without use. A run that waits longer than that for a deferred tool pays the full input price for its whole prompt on the next turn, instead of the cache-read price. For a long conversation history this can be most of the cost of the turn.

The admin agent page lists every turn with the cache read and cache creation tokens of its completion, so you can see when a resume missed the cache. If the cost matters, keep the context of agents that wait small, or set a shorter deadline.

# Migrations

This feature adds the `raif_agent_turns` table and columns on `raif_agents`, `raif_model_tool_invocations`, and `raif_conversation_entries`. Run `rails raif:install:migrations` and `rails db:migrate` when you upgrade.
