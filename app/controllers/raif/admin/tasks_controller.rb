# frozen_string_literal: true

module Raif
  module Admin
    class TasksController < Raif::Admin::ApplicationController
      def index
        @task_types = Raif::Task.distinct.pluck(:type)
        @selected_type = params[:task_types].present? ? params[:task_types] : "all"

        @task_statuses = [:all, :completed, :failed, :in_progress, :pending]
        @selected_statuses = params[:task_statuses].present? ? params[:task_statuses].to_sym : :all

        @selected_llm_model_key = params[:llm_model_key].presence
        @llm_model_keys = Raif::Task.distinct.order(:llm_model_key).pluck(:llm_model_key)

        tasks = Raif::Task.order(created_at: :desc)
        tasks = tasks.where(type: @selected_type) if @selected_type.present? && @selected_type != "all"

        if @selected_statuses.present? && @selected_statuses != :all
          case @selected_statuses
          when :completed
            tasks = tasks.completed
          when :failed
            tasks = tasks.failed
          when :in_progress
            tasks = tasks.in_progress
          when :pending
            tasks = tasks.pending
          end
        end

        tasks = tasks.where(llm_model_key: @selected_llm_model_key) if @selected_llm_model_key.present?

        @pagy, @tasks = pagy(tasks)
      end

      def show
        @task = Raif::Task.includes(:raif_model_completion).find(params[:id])
      end
    end
  end
end
