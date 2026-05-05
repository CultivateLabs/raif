# frozen_string_literal: true

module Raif
  # Default completion handler for batches whose child Raif::ModelCompletions
  # were created via Raif::Task.build_for_batch / Raif::Task#prepare_for_batch!.
  #
  # The typical pattern is to subclass and register a completion block:
  #
  #   class MyConsumer::BatchHandler < Raif::TaskBatchCompletionHandler
  #     on_batch_completion do
  #       # Inside the block, `batch` and `tasks` are available:
  #       #   batch -> the Raif::ModelCompletionBatch (terminal status)
  #       #   tasks -> Array<Raif::Task> already hydrated via #process_completion!
  #       # Plus any helper methods you define on the subclass.
  #       successful = tasks.select(&:completed?)
  #       MyConsumer::Aggregator.combine(successful)
  #     end
  #   end
  #
  # Then point the batch at the handler when you create it:
  #
  #   batch = Raif::ModelCompletionBatches::Anthropic.create!(
  #     llm_model_key: ...,
  #     model_api_name: ...,
  #     completion_handler_class_name: "MyConsumer::BatchHandler"
  #   )
  #
  # Lifecycle when Raif::PollModelCompletionBatchJob fires the handler:
  #   1. Each child Raif::ModelCompletion is routed through its source
  #      Raif::Task#process_completion!, which mirrors the synchronous path's
  #      success/failure transitions. Idempotent: tasks already in a terminal
  #      state are skipped (safe for replays).
  #   2. The registered on_batch_completion block runs.
  #
  # Per-task hydration errors are caught and logged so one bad task doesn't
  # block the rest of the batch. Errors raised from the on_batch_completion
  # block propagate to the caller (typically Raif::PollModelCompletionBatchJob).
  #
  # Inside the block, use `next` for early exits -- `return` would try to
  # return from the enclosing method scope and raise LocalJumpError.
  class TaskBatchCompletionHandler

    class_attribute :batch_completion_block, instance_writer: false, instance_accessor: false

    class << self
      # DSL: registers the block to run after hydration. The block is
      # evaluated against an instance of the handler with `batch` and `tasks`
      # exposed as readers.
      def on_batch_completion(&block)
        self.batch_completion_block = block
      end

      # Entry point invoked by Raif::ModelCompletionBatch#dispatch_completion_handler!.
      def handle_batch_completion(batch)
        tasks = hydrate_tasks(batch)

        if batch_completion_block
          new(batch, tasks).instance_exec(&batch_completion_block)
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
