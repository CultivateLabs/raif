# frozen_string_literal: true

module Raif
  class PromptStudioTaskRunJob < ApplicationJob

    def perform(task:)
      task.run
      broadcast_task_result(task)
    rescue StandardError => e
      logger.error "Error running prompt studio task: #{e.message}"
      logger.error e.backtrace&.join("\n")

      task.update(failed_at: Time.current) unless task.failed_at?
      broadcast_task_result(task)
    end

  private

    def broadcast_task_result(task)
      comparison = Raif::PromptStudioComparisonBuilder.build(task)
      original_task = task.prompt_studio_run? && task.source.is_a?(Raif::Task) ? task.source : nil

      html = Raif::Admin::PromptStudio::TasksController.render(
        partial: "raif/admin/prompt_studio/tasks/task_result",
        locals: { task: task, comparison: comparison, original_task: original_task }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        task,
        target: ActionView::RecordIdentifier.dom_id(task, :result),
        html: html
      )
    end

  end
end
