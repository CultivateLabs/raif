---
layout: default
title: Archiving
nav_order: 6.5
description: "Archive and cull old model completion and task rows to object storage"
---

{% include table-of-contents.md %}

# Archiving

`raif_model_completions` and `raif_tasks` grow without bound. Both hold full prompts and responses, so a busy application accumulates large tables and a large amount of sensitive text.

Raif can archive rows older than a retention period to object storage as gzip JSONL and then delete them. It is **disabled by default and never deletes anything until you opt in**.

Two jobs share one implementation (`Raif::ArchiveJob`) and one set of safety invariants:

| Job | Archives | Retention setting |
|---|---|---|
| `Raif::ArchiveModelCompletionsJob` | `raif_model_completions` | `model_completion_retention_period` |
| `Raif::ArchiveTasksJob` | `raif_tasks`, plus their `raif_model_tool_invocations` | `task_retention_period` |

Everything below applies to both unless it says otherwise.

## How a run works

Each run processes one batch at a time:

1. Select records that are old enough and safe to remove (see [Eligibility](#eligibility)).
2. Serialize the batch to gzip JSONL and upload it to your storage adapter.
3. Record a `Raif::Archive` audit row, but only after the upload succeeded.
4. Delete the archived records.

The ordering is the safety property: **a record is never deleted unless this run already uploaded it**. A crash before the deletion commits leaves the rows in place, and the next run re-archives them under a new key rather than resuming or overwriting; once it commits, the archive holding those rows already exists. There is no in-flight state to repair.

The cost of that guarantee is duplicates. A crash between the upload and the audit-row insert leaves an object in storage that no `Raif::Archive` row references. Those rows were not deleted, so they archive again next run, and the orphaned object is harmless. This is why storage policy has to be prefix-wide (see [Storage requirements](#storage-requirements)).

## Enabling it

`archive_enabled`, `archive_storage` and the resource's retention period must all be present before anything is archived. If any is missing, that job returns without touching a row.

```ruby
Raif.configure do |config|
  config.archive_enabled = true
  config.archive_storage = Raif::ArchiveStorage::FileSystem.new(root: Rails.root.join("storage", "raif-archives"))
  config.model_completion_retention_period = 6.months
  config.task_retention_period = 6.months
end
```

Each retention period must be at least 1 month, and defaults to `nil`, which disables culling of that resource even when `archive_enabled` is true. The two are independent: enabling one does not enable the other.

## Scheduling

Raif does not schedule the jobs for you. Run them yourself, typically nightly:

```ruby
Raif::ArchiveModelCompletionsJob.perform_later
Raif::ArchiveTasksJob.perform_later
```

Run the completion job first. A task is never culled while its completion row survives, so a task becomes eligible on the run after its completion is archived.

Three budgets bound the work per run: `max_records`, `max_objects`, and `max_runtime`. The same code drains a multi-year backlog gradually and handles steady state, so a first run on a large table is safe. Concurrent runs are excluded by an advisory lock. The runtime budget is only checked between objects, so a started object always finishes and a run always stops in a safe state.

Also schedule `Raif::RepairInferenceCostEventsJob` (e.g. daily). Terminal completions whose cost event is missing or stale are never culled, and the repair job is what lets those rows self-heal instead of accumulating forever.

## Previewing before you enable

`dry_run` writes nothing and can be run at any time, including while `archive_enabled` is still false:

```ruby
Raif::ArchiveModelCompletionsJob.dry_run
Raif::ArchiveTasksJob.dry_run
```

It reports what a run would archive, split by terminal state, plus the per-guard exclusions among cutoff-aged records, and (with partitioning) per-partition counts alongside the `excluded_by_missing_partition` count.

## Storage requirements

Archives contain full prompts and responses. **The storage target must be private, encrypted, and access-controlled at least as strictly as your application database.**

Apply that policy, and any lifecycle rules, to **whole prefixes** rather than deriving it from `raif_archives` rows. A crashed run can leave an uploaded object that no row references, so a policy driven by the audit table would miss it. Prefix-wide coverage is also what makes `Raif::Archive.purge_partition!` complete: it erases a partition's entire prefix, crash-orphaned objects included.

When partitioning is off the prefixes are `raif-archives/model-completions/`, `raif-archives/tasks/` and `raif-archives/model-tool-invocations/`. When it is on, every prefix under `raif-archives/partitions/`.

## Storage adapters

Raif ships `Raif::ArchiveStorage::FileSystem` for local disk. Production applications typically supply their own, commonly S3-backed. An adapter is any object implementing:

| Method | Required | Contract |
|---|---|---|
| `write(key:, io:, checksum_sha256:)` | Always | Uploads and returns a nonblank location string. Must raise on any failure. |
| `delete(key:)` | For tainted-upload cleanup | Idempotent: a missing object succeeds. |
| `delete_prefix(prefix:)` | For `purge_partition!` | Recursive delete returning the object count. Idempotent. |

`delete` and `delete_prefix` must raise `Raif::Errors::ArchiveStorageError` on failure.

Pass `checksum_sha256` through to your store where it supports it (for example on an S3 `PUT`) so integrity is verified server-side. Note that raif supplies a lowercase hex digest; some SDKs expect Base64 of the raw bytes.

## Eligibility

### Model completions

A completion is archived and deleted only when all of these hold:

- It was created before the retention cutoff, frozen at the start of the run.
- It has been quiescent, meaning it has not been updated recently.
- It is not a member of a model completion batch that is still non-terminal.
- **Terminal rows only:** its `Raif::InferenceCostEvent` exists and is at least as fresh as the completion. A stale event means a post-terminal update committed but the event re-sync failed, so the spend data may be wrong. The row waits until `Raif::RepairInferenceCostEventsJob` re-syncs it.
- Its citations, if any, have already been copied to its `Raif::ConversationEntry` source.

### Tasks

A task is archived and deleted only when all of these hold:

- It was created before the retention cutoff, frozen at the start of the run.
- It has been quiescent, meaning it has not been updated recently.
- **The completion gate:** no `Raif::ModelCompletion` row still names it as its source. `Raif::Task` declares `has_one :raif_model_completion, dependent: :destroy`, which a bulk delete does not run, so culling a task out from under a live completion would leave that completion pointing at nothing. Waiting costs nothing: the completion is archived first, and the task follows on a later run.
- **The prompt studio gate:** no `raif_prompt_studio_batch_run_items` row references it. That table's three task foreign keys all `RESTRICT`, so deleting a referenced task would raise and take the whole cull down with it. Prompt studio rows are never deleted, so a task a batch run touched is retained indefinitely, by design.

A task's `raif_model_tool_invocations` are archived with it, as their own object under the same partition prefix, and deleted in the same transaction. They cannot ride inside the task's object, because each object holds one table and its manifest declares that table's columns. They also cannot be swept up afterwards: `raif_model_tool_invocations` has no partition column of its own, and the only thing that can place an invocation in a partition is the task it belongs to.

### Nonterminal rows

Nonterminal completions skip the cost-event guard, because they never reached a terminal state and so have no spend to protect. Nonterminal tasks are archived on the same terms. These are pending rows orphaned by killed processes and crashed jobs, and they would otherwise be immortal.

They are archived through the same path as everything else rather than deleted outright, so that "every deleted row exists in an archive" holds without exception. Because they have no cost event, **no per-record link back to their archive survives**. Recovering one means searching candidate archive objects by hand.

## Cost reporting is unaffected

Culling a completion does not lose its spend. Each `Raif::InferenceCostEvent` survives the deletion and is stamped with the `Raif::Archive` it was culled into, so historical cost reporting is complete whether or not the underlying completion still exists.

`raif_model_completion_batches` rows are deliberately left alone. They carry their own aggregated cost columns, and nothing recomputes those from children after finalization.

A culled task is stamped the same way, on `raif_task_archive_id`. Both stamps can be set on one event: a task and its completion are archived by different jobs into different objects, and an event routinely outlives its completion while its task is still retained.

## Finding an archived record in the admin

The raif admin resolves a culled row from the stamp on its surviving `Raif::InferenceCostEvent`:

- A task page for a culled task id renders its archive link, model and cost data instead of raising.
- A completion section on a task page renders the same way once the completion is culled.

The stamp is the only proof. An event whose record is gone but that carries no stamp belongs to a row deleted outside the archive job, so the admin treats it as missing rather than claiming it was archived. A nonterminal task never produced a cost event, so nothing survives it and its id 404s.

## Partitioning and per-tenant archive erasure

Setting a partition column makes it possible to erase all archived data belonging to one tenant:

```ruby
config.archive_partition_column = :account_id
```

The column must exist on every archived resource whose job you schedule. `raif_model_tool_invocations` is the exception: it has no column of its own, and each invocation inherits the partition of the task it belongs to.

Every archive object then holds records from exactly one partition and is stored under that partition's own key prefix. `Raif::Archive.purge_partition!` can then erase that tenant's archived data:

```ruby
Raif::Archive.purge_partition!(partition_value: account.id)
```

That deletes the partition's entire storage prefix (crash-orphaned uploads included), nullifies surviving cost event stamps, and deletes its `Raif::Archive` rows.

**This covers archived data only.** Live `Raif::ModelCompletion` and `Raif::Task` rows, and the `Raif::InferenceCostEvent` records themselves, are not deleted, so treat it as one step in a tenant-deletion workflow rather than the whole of it.

Work is scheduled in round-robin passes, at most one object per partition per pass, visiting eligible partitions oldest-first. Many small partitions drain within a single run while one large-backlog partition cannot monopolize it.

### The immutability contract

**The partition column's value must be immutable for a record's lifetime.** Pair a `NOT NULL` column with `attr_readonly` and `config.active_record.raise_on_assign_to_attr_readonly`:

```ruby
Raif::ModelCompletion.attr_readonly(:account_id)
Raif::Task.attr_readonly(:account_id)
```

A record that changes partitions mid-archival can leave a copy under its old prefix that the new partition's purge will never find. Raif detects the case it can, aborting the cull and cleaning up the object, but that cannot close every crash window, which is why immutability remains a hard requirement rather than a suggestion.

### Records with no partition value

By default a record whose partition value is `NULL` (or normalizes to blank) **fails closed**: it is never archived, and `dry_run` reports it under `excluded_by_missing_partition`. This is deliberate, so a later tenant purge cannot miss records that lost their attribution.

If you have intentionally global or unowned records, opt them in explicitly:

```ruby
config.archive_partition_fallback = Raif::ArchivePartition::UNGROUPED
```

They are then archived under a reserved `_ungrouped` storage segment that `purge_partition!` never touches.

### Two limitations

- **No raw identifiers in storage paths.** Paths carry only a SHA-256 token of the normalized value. The raw value lives on the `Raif::Archive` row, and the token is re-derivable from any candidate value.
- **Enabling partitioning does not retrofit.** Archives created before you set a partition column remain blended and stay outside partition purge coverage.

Column existence is checked when the job or `dry_run` executes, not at boot, so a blank-database boot (`db:create`, `db:migrate`, asset precompile) keeps working.
