# frozen_string_literal: true

module Raif
  # Default completion handler for batches whose child Raif::ModelCompletions
  # were created via Raif::Task.build_for_batch / Raif::Task#prepare_for_batch!.
  #
  # The typical pattern is to subclass and register one or more lifecycle
  # blocks. Three are available:
  #
  #   - on_batch_completion fires for every terminal status (ended, canceled,
  #     expired, failed). Use it for unconditional teardown / observability,
  #     or as a one-block catchall when you don't need to branch on outcome.
  #   - on_batch_success fires only when batch.successful? (status == "ended").
  #     The tasks array is populated with hydrated Raif::Tasks whose results
  #     were applied from the provider response.
  #   - on_batch_failure fires only when the batch reached a non-success
  #     terminal status (canceled / expired / failed). The per-entry fetch was
  #     skipped, so tasks are all in `failed` state with no useful
  #     parsed_response; the meaningful state is on the batch itself
  #     (failure_reason, failure_error, status, metadata).
  #
  # Any combination is valid: just the catchall, just success+failure, or all
  # three (e.g. log + branch). When all three are registered, on_batch_completion
  # fires first, then exactly one of on_batch_success or on_batch_failure.
  #
  #   class MyConsumer::BatchHandler < Raif::TaskBatchCompletionHandler
  #     on_batch_success do
  #       successful = tasks.select(&:completed?)
  #       MyConsumer::Aggregator.combine(successful)
  #     end
  #
  #     on_batch_failure do
  #       MyConsumer::FailureNotifier.notify(batch.failure_reason, batch.metadata)
  #     end
  #   end
  #
  # Then point the batch at the handler when you create it:
  #
  #   batch = llm.create_batch(
  #     completion_handler_class_name: "MyConsumer::BatchHandler",
  #     metadata: { ... }
  #   )
  #
  # Lifecycle when Raif::PollModelCompletionBatchJob fires the handler:
  #   1. Each child Raif::ModelCompletion is routed through its source
  #      Raif::Task#process_completion!, which mirrors the synchronous path's
  #      success/failure transitions. Idempotent: tasks already in a terminal
  #      state are skipped (safe for replays).
  #   2. The registered blocks run in order: on_batch_completion (if any),
  #      then on_batch_success or on_batch_failure (whichever applies).
  #
  # Per-task hydration errors are caught and logged so one bad task doesn't
  # block the rest of the batch. Errors raised from a registered block
  # propagate to the caller (typically Raif::PollModelCompletionBatchJob).
  #
  # Inside any block, use `next` for early exits -- `return` would try to
  # return from the enclosing method scope and raise LocalJumpError.
  class TaskBatchCompletionHandler

    class_attribute :batch_completion_block, instance_writer: false, instance_accessor: false
    class_attribute :batch_success_block,    instance_writer: false, instance_accessor: false
    class_attribute :batch_failure_block,    instance_writer: false, instance_accessor: false

    class << self
      # DSL: registers a block to run after hydration for every terminal
      # status. The block is evaluated against an instance of the handler
      # with `batch` and `tasks` exposed as readers.
      def on_batch_completion(&block)
        self.batch_completion_block = block
      end

      # DSL: registers a block to run after hydration when the batch reached
      # the `ended` terminal status (per-entry results applied to each child).
      def on_batch_success(&block)
        self.batch_success_block = block
      end

      # DSL: registers a block to run after hydration when the batch reached
      # a non-success terminal status (canceled / expired / failed).
      def on_batch_failure(&block)
        self.batch_failure_block = block
      end

      # Entry point invoked by Raif::ModelCompletionBatch#dispatch_completion_handler!.
      def handle_batch_completion(batch)
        tasks = hydrate_tasks(batch)
        instance = new(batch, tasks)

        instance.instance_exec(&batch_completion_block) if batch_completion_block

        if batch.successful?
          instance.instance_exec(&batch_success_block) if batch_success_block
        elsif batch_failure_block
          instance.instance_exec(&batch_failure_block)
        end
      end

      # Walks each child Raif::ModelCompletion and routes it through its
      # source Raif::Task. Returns the array of Raif::Task records that were
      # attached to the batch (including any whose hydration raised, so
      # consumers can filter on terminal state).
      #
      # Tasks already in a terminal state (completed? or failed?) are
      # returned without re-processing -- safe for replays / re-dispatched
      # batches.
      #
      # Calling Raif::Task#process_completion! on a child whose model
      # completion was force-failed (whole-batch canceled / expired / failed)
      # correctly transitions the task to failed; callers do not need to
      # special-case whole-batch failures here.
      def hydrate_tasks(batch)
        tasks = []

        batch.raif_model_completions.includes(:source).find_each do |mc|
          task = mc.source
          unless task.is_a?(Raif::Task)
            Raif.logger.warn(
              "Raif::TaskBatchCompletionHandler: Raif::ModelCompletion ##{mc.id} in batch ##{batch.id} " \
                "has source=#{task.inspect}, expected a Raif::Task. Skipping."
            )
            next
          end

          tasks << task

          next if task.completed? || task.failed?

          begin
            task.process_completion!(mc)
          rescue StandardError => e
            Raif.logger.error(
              "Raif::TaskBatchCompletionHandler: failed to process Raif::Task ##{task.id} " \
                "(batch ##{batch.id}, completion ##{mc.id}): #{e.class}: #{e.message}"
            )
            Raif.logger.error(e.backtrace.first(20).join("\n")) if e.backtrace.present?

            if defined?(Airbrake)
              notice = Airbrake.build_notice(e)
              notice[:context][:component] = "raif_task_batch_completion_handler"
              notice[:params] = { batch_id: batch.id, task_id: task.id, model_completion_id: mc.id }
              Airbrake.notify(notice)
            end
          end
        end

        tasks
      end
    end

    attr_reader :batch, :tasks

    def initialize(batch, tasks)
      @batch = batch
      @tasks = tasks
    end

  end
end
