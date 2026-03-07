# frozen_string_literal: true

module Raif
  class PromptStudioTaskRunJob < ApplicationJob

    def perform(task:)
      task.run
      broadcast_task_result(task)
    rescue StandardError => e
      logger.error "Error running prompt studio task: #{e.message}"
      logger.error e.backtrace.join("\n")

      task.update(failed_at: Time.current) unless task.failed_at?
      broadcast_task_result(task)
    end

  private

    def broadcast_task_result(task)
      comparison = build_comparison(task)

      Turbo::StreamsChannel.broadcast_replace_to(
        task,
        target: ActionView::RecordIdentifier.dom_id(task, :result),
        partial: "raif/admin/prompt_studio/tasks/task_result",
        locals: { task: task, comparison: comparison }
      )
    end

    def build_comparison(task)
      current_prompt = begin
        task.build_prompt
      rescue StandardError
        nil
      end

      current_system_prompt = begin
        task.build_system_prompt
      rescue StandardError
        nil
      end

      {
        original_prompt: task.prompt,
        original_system_prompt: task.system_prompt,
        current_prompt: current_prompt,
        current_system_prompt: current_system_prompt,
        prompt_changed: task.prompt.present? && current_prompt.present? && task.prompt.strip != current_prompt.strip,
        system_prompt_changed: task.system_prompt.present? && current_system_prompt.present? && task.system_prompt.strip != current_system_prompt.strip,
        warnings: []
      }
    end

  end
end
