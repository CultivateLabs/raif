# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class BatchRunsController < BaseController
        def create
          unless prompt_studio_runs_enabled?
            redirect_to raif.admin_prompt_studio_tasks_path, alert: t("raif.admin.prompt_studio.common.runs_disabled")
            return
          end

          source_tasks = resolve_source_tasks
          if source_tasks.empty?
            redirect_to raif.admin_prompt_studio_tasks_path(task_type: params[:task_type]),
              alert: t("raif.admin.prompt_studio.batch_runs.create.no_tasks_selected")
            return
          end

          available_keys = Raif.available_llm_keys.map(&:to_s)

          unless params[:llm_model_key].present? && available_keys.include?(params[:llm_model_key])
            redirect_to raif.admin_prompt_studio_tasks_path(task_type: params[:task_type]),
              alert: t("raif.admin.prompt_studio.tasks.rerun.invalid_model")
            return
          end

          if params[:judge_type].present? && params[:judge_llm_model_key].present? && !available_keys.include?(params[:judge_llm_model_key])
            redirect_to raif.admin_prompt_studio_tasks_path(task_type: params[:task_type]),
              alert: t("raif.admin.prompt_studio.tasks.rerun.invalid_model")
            return
          end

          batch_run = Raif::PromptStudioBatchRun.new(
            task_type: params[:task_type],
            llm_model_key: params[:llm_model_key],
            judge_type: params[:judge_type].presence,
            judge_llm_model_key: params[:judge_llm_model_key].presence,
            judge_config: build_judge_config,
            total_count: source_tasks.size
          )

          batch_run.save!

          source_tasks.each do |task|
            batch_run.items.create!(source_task: task)
          end

          Raif::PromptStudioBatchRunJob.perform_later(batch_run: batch_run)

          redirect_to raif.admin_prompt_studio_batch_run_path(batch_run)
        rescue StandardError => e
          redirect_to raif.admin_prompt_studio_tasks_path(task_type: params[:task_type]),
            alert: t("raif.admin.prompt_studio.batch_runs.create.error", message: e.message)
        end

        def show
          @batch_run = Raif::PromptStudioBatchRun.find(params[:id])
          items = @batch_run.items.includes(:source_task, :result_task, :judge_task).order(:id)
          @pagy, @items = pagy(items)
        end

      private

        def resolve_source_tasks
          ids = Array(params[:source_task_ids]).map(&:to_i).reject(&:zero?)
          scope = Raif::Task.where(id: ids).completed
          scope = scope.where(type: params[:task_type]) if params[:task_type].present?
          scope
        end

        def build_judge_config
          config = case params[:judge_type]
          when "Raif::Evals::LlmJudges::Binary"
            {
              "criteria" => params[:judge_criteria].presence || "",
              "strict_mode" => params[:judge_strict_mode] == "1"
            }
          when "Raif::Evals::LlmJudges::Scored"
            {
              "scoring_rubric" => params[:judge_scoring_rubric].presence || "accuracy"
            }
          when "Raif::Evals::LlmJudges::Comparative"
            {
              "comparison_criteria" => params[:judge_comparison_criteria].presence || ""
            }
          when "Raif::Evals::LlmJudges::Summarization"
            {}
          else
            {}
          end

          if params[:judge_type].present?
            config["include_original_prompt_as_context"] = params[:judge_include_original_prompt_as_context] == "1"
          end

          config
        end
      end
    end
  end
end
