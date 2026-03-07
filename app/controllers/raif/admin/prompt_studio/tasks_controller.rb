# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class TasksController < BaseController
        def index
          @task_types = Raif::Task.distinct.pluck(:type).sort
          @selected_type = params[:task_type] if params[:task_type].present?

          if @selected_type.present?
            tasks = Raif::Task.where(type: @selected_type).completed.order(created_at: :desc)
            @pagy, @tasks = pagy(tasks)
          end
        end

        def show
          @task = Raif::Task.find(params[:id])
          @comparison = build_prompt_comparison(@task)
          @available_llm_keys = Raif.available_llm_keys.map(&:to_s).sort
        end

        def create
          original_task = Raif::Task.find(params[:source_task_id])

          unless prompt_studio_runs_enabled?
            redirect_to raif.admin_prompt_studio_task_path(original_task), alert: t("raif.admin.prompt_studio.common.runs_disabled")
            return
          end

          llm_model_key = params[:llm_model_key]

          unless llm_model_key.present? && Raif.available_llm_keys.map(&:to_s).include?(llm_model_key)
            redirect_to raif.admin_prompt_studio_task_path(original_task), alert: t("raif.admin.prompt_studio.tasks.rerun.invalid_model")
            return
          end

          new_task = original_task.class.new(
            creator: original_task.creator,
            source: original_task.source,
            llm_model_key: llm_model_key,
            available_model_tools: original_task.available_model_tools,
            run_with: original_task.run_with,
            prompt_studio_run: true,
            started_at: Time.current
          )
          new_task.assign_attributes(original_task.prompt_studio_rerun_attributes)

          new_task.save!
          Raif::PromptStudioTaskRunJob.perform_later(task: new_task)

          redirect_to raif.admin_prompt_studio_task_path(new_task)
        rescue StandardError => e
          new_task&.update(failed_at: Time.current) unless new_task&.failed_at?
          redirect_to raif.admin_prompt_studio_task_path(original_task || params[:source_task_id]),
            alert: t("raif.admin.prompt_studio.tasks.rerun.error", message: e.message)
        end
      end
    end
  end
end
