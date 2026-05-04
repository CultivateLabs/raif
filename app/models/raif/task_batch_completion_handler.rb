# frozen_string_literal: true

module Raif
  # Default completion handler for batches whose child Raif::ModelCompletions
  # were created via Raif::Task.build_for_batch / Raif::Task#prepare_for_batch!.
  #
  # Set on the batch when it's created:
  #
  #   batch = Raif::ModelCompletionBatches::Anthropic.create!(
  #     llm_model_key: ...,
  #     model_api_name: ...,
  #     completion_handler_class_name: "Raif::TaskBatchCompletionHandler"
  #   )
  #
  # The polling job calls Raif::TaskBatchCompletionHandler.handle_batch_completion(batch)
  # once the batch reaches a terminal status. We walk each child completion,
  # locate its source Raif::Task (set by prepare_for_batch!), and route the
  # result through Raif::Task#process_completion! so success vs. failure is
  # handled identically to the synchronous path.
  #
  # Per-task errors are caught and logged so one bad task doesn't block the
  # rest of the batch from being processed.
  class TaskBatchCompletionHandler

    def self.handle_batch_completion(batch)
      batch.raif_model_completions.includes(:source).find_each do |mc|
        task = mc.source
        unless task.is_a?(Raif::Task)
          Raif.logger.warn(
            "Raif::TaskBatchCompletionHandler: Raif::ModelCompletion ##{mc.id} in batch ##{batch.id} " \
              "has source=#{task.inspect}, expected a Raif::Task. Skipping."
          )
          next
        end

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
    end

  end
end
