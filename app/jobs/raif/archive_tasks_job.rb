# frozen_string_literal: true

module Raif
  # Archives Raif::Task rows older than Raif.config.task_retention_period to
  # Raif.config.archive_storage as gzip JSONL, then deletes them.
  # Raif::ArchiveJob owns the batching, partitioning and cull machinery and
  # documents the invariants; this class contributes the eligibility rules
  # and the handling of the rows that point at a task.
  #
  # A task's spend lives on its Raif::ModelCompletion's
  # Raif::InferenceCostEvent, so this job has no durability guard of its own.
  # What it has instead is the completion gate: it never culls a task whose
  # completion row is still present.
  class ArchiveTasksJob < ArchiveJob
    # Key prefix when partitioning is unset.
    KEY_PREFIX = "raif-archives/tasks"
    # Resource segment below a partition prefix:
    # raif-archives/partitions/<token>/tasks/<object>
    RESOURCE_KEY_SEGMENT = "tasks"
    # Model tool invocations travel with their task, in their own object
    # under the task's partition prefix.
    INVOCATIONS_KEY_PREFIX = "raif-archives/model-tool-invocations"
    INVOCATIONS_RESOURCE_KEY_SEGMENT = "model-tool-invocations"

    class << self
      def archived_class
        Raif::Task
      end

      def retention_period
        Raif.config.task_retention_period
      end

      def retention_config_name
        "task_retention_period"
      end

      def key_prefix
        KEY_PREFIX
      end

      def resource_key_segment
        RESOURCE_KEY_SEGMENT
      end

      # A task is safe to archive and delete only when ALL hold:
      #
      # - created_at is before the (job-frozen) retention cutoff
      # - it has been quiescent: not updated within QUIESCENCE_PERIOD
      # - completion gate: no Raif::ModelCompletion row still names it as its
      #   source. Raif::Task declares has_one :raif_model_completion with
      #   dependent: :destroy, which a bulk delete does not run, so culling a
      #   task out from under a live completion would leave that completion
      #   pointing at nothing - and the raif admin resolves a completion's
      #   source on every render. Waiting is free: the completion job archives
      #   the completion first, and this job takes the task on a later run.
      # - prompt studio gate: no raif_prompt_studio_batch_run_items row
      #   references it. That table's source_task_id is NOT NULL and all
      #   three of its task foreign keys RESTRICT, so deleting a referenced
      #   task raises and takes the whole cull down with it. Prompt studio
      #   rows are never deleted, so a task a batch run touched is retained
      #   indefinitely, by design.
      #
      # Nonterminal tasks (the residue of killed processes and crashed jobs)
      # are archived like any other, so "every deleted task exists in an
      # archive" holds without exception.
      def eligible_scope(cutoff)
        quiescent_scope(cutoff)
          .where.not(id: tasks_with_live_model_completion)
          .where.not(prompt_studio_referenced_sql)
      end

      def dry_run_exclusions(cutoff)
        {
          excluded_by_live_model_completion: base_scope(cutoff).where(id: tasks_with_live_model_completion).count,
          excluded_by_prompt_studio: base_scope(cutoff).where(prompt_studio_referenced_sql).count
        }
      end

    private

      # source_id is nullable on raif_model_completions, and a single NULL in
      # a NOT IN subquery makes the whole predicate never true, so the NULLs
      # are filtered out here rather than in the caller.
      def tasks_with_live_model_completion
        Raif::ModelCompletion
          .where(source_type: "Raif::Task")
          .where.not(source_id: nil)
          .select(:source_id)
      end

      # EXISTS rather than three NOT IN subqueries: it spans all three
      # indexed columns in one pass, and it is NULL-safe, which matters
      # because result_task_id and judge_task_id are nullable.
      def prompt_studio_referenced_sql
        items = Raif::PromptStudioBatchRunItem.table_name
        tasks = Raif::Task.table_name
        conditions = [:source_task_id, :result_task_id, :judge_task_id]
          .map { |column| "#{items}.#{column} = #{tasks}.id" }
          .join(" OR ")

        "EXISTS (SELECT 1 FROM #{items} WHERE #{conditions})"
      end
    end

  private

    # A task's cost events keep pointing at it after the row is gone (source
    # is polymorphic and unconstrained), so the stamp is what separates an
    # archived task from one deleted some other way. The raif admin's
    # archived-task view requires it.
    #
    # No count assertion, unlike the completion stamp: a terminal task that
    # fails before its completion exists never produces a cost event, and the
    # completion gate already made the spend durable.
    def stamp_cost_events!(archive, terminal_ids)
      return if terminal_ids.empty?

      Raif::InferenceCostEvent
        .where(source_type: "Raif::Task", source_id: terminal_ids)
        .update_all(raif_task_archive_id: archive.id)
    end

    # Uploads the batch's Raif::ModelToolInvocation rows as their own
    # object(s), before the cull transaction opens. They cannot ride inside
    # the task object, because Raif::ArchiveSerializer writes one table per
    # object. They cannot be swept up afterwards either:
    # raif_model_tool_invocations has no partition column, so only the parent
    # task can place an invocation in a partition, and by then it is deleted.
    # They go under the parent batch's partition prefix.
    def archive_dependents!(archived_ids, cutoff, partition)
      @archived_invocation_ids = []
      remaining = invocation_ids_for(archived_ids)
      archives = []

      while remaining.any?
        serialized = serialize_invocations(remaining, cutoff, partition)

        begin
          written = serialized[:record_ids]
          # Only reachable if the rows vanished between the pluck and the
          # serialize, in which case there is nothing left to archive.
          break if written.empty?

          archives << upload_archive!(
            serialized: serialized,
            resource_type: Raif::ModelToolInvocation.name,
            key: build_key(partition, written, INVOCATIONS_RESOURCE_KEY_SEGMENT, INVOCATIONS_KEY_PREFIX),
            cutoff: cutoff,
            partition: partition,
            record_ids: written
          )

          @archived_invocation_ids.concat(written)
          remaining -= written
        ensure
          File.unlink(serialized[:path]) if File.exist?(serialized[:path])
        end
      end

      archives
    end

    # Only the invocations this run actually uploaded, and only those whose
    # task is being deleted in this transaction: a task that fell out of the
    # eligibility recheck keeps its invocations, and re-archives with them.
    def delete_dependents!(deletable_ids)
      return if @archived_invocation_ids.blank?

      Raif::ModelToolInvocation
        .where(id: @archived_invocation_ids, source_type: "Raif::Task", source_id: deletable_ids)
        .in_batches(of: 5_000)
        .delete_all
    end

    def invocation_ids_for(archived_ids)
      Raif::ModelToolInvocation
        .where(source_type: "Raif::Task", source_id: archived_ids)
        .order(:id)
        .pluck(:id)
    end

    def serialize_invocations(ids, cutoff, partition)
      Raif::ArchiveSerializer.new(
        relation: Raif::ModelToolInvocation.where(id: ids),
        cutoff_at: cutoff,
        byte_limit: self.class::BATCH_UNCOMPRESSED_BYTE_LIMIT,
        # Named for the column it was read from, which is on the parent task,
        # not on this row. A reader of the object must not go looking for a
        # column raif_model_tool_invocations does not have.
        partition_column: partition && "#{Raif::Task.table_name}.#{self.class.partition_column}",
        partition_value: partition&.value
      ).serialize
    end

  end
end
