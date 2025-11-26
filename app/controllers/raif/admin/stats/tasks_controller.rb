# frozen_string_literal: true

module Raif
  module Admin
    module Stats
      class TasksController < Raif::Admin::ApplicationController
        def index
          @selected_period = params[:period] || "day"
          @time_range = get_time_range(@selected_period)
          @show_model_breakdown = params[:show_model_breakdown] == "1"

          @task_count = Raif::Task.where(created_at: @time_range).count

          group_columns = @show_model_breakdown ? [:type, :llm_model_key] : [:type]
          select_columns = ["raif_tasks.type"]
          select_columns << "raif_tasks.llm_model_key" if @show_model_breakdown
          select_columns << "COUNT(raif_tasks.id)"
          select_columns << "SUM(raif_model_completions.prompt_token_cost)"
          select_columns << "SUM(raif_model_completions.output_token_cost)"
          select_columns << "SUM(raif_model_completions.total_cost)"
          select_columns.compact!

          @task_stats_by_type = Raif::Task.joins(:raif_model_completion)
            .where(created_at: @time_range)
            .group(*group_columns)
            .pluck(*select_columns)
            .map do |type, *rest|
              llm_model_key = @show_model_breakdown ? rest.shift : nil
              Raif::Admin::TaskStat.new(type, llm_model_key, *rest)
            end
        end
      end
    end
  end
end
