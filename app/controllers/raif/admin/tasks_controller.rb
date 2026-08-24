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
        @task = Raif::Task.includes(:raif_model_completion).find_by(id: params[:id])
        return render_archived_task if @task.nil?

        # When the completion row has been archived and culled, its durable
        # cost/token record still renders (with an "archived" badge linking
        # to its Raif::Archive). Stamp-only: an event without raif_archive_id
        # belongs to a completion deleted outside the archive job, which was
        # never archived, so nothing may claim it was.
        if @task.raif_model_completion.blank?
          @archived_inference_cost_event = Raif::InferenceCostEvent
            .where(source: @task, raif_model_completion_id: nil)
            .where.not(raif_archive_id: nil)
            .order(:id)
            .last
        end
      end

    private

      # The task row was culled. Its cost event outlives it and still points
      # at the id, so the event carries what is left to show. An event with no
      # raif_task_archive_id belongs to a task deleted outside the archive
      # job, so it stays a 404 rather than claiming an archive.
      def render_archived_task
        @archived_task_id = params[:id]
        @archived_task_event = Raif::InferenceCostEvent
          .where(source_type: "Raif::Task", source_id: @archived_task_id)
          .where.not(raif_task_archive_id: nil)
          .order(:id)
          .last

        raise ActiveRecord::RecordNotFound if @archived_task_event.nil?

        render :archived
      end
    end
  end
end
