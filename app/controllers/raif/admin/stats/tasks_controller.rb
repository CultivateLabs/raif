# frozen_string_literal: true

module Raif
  module Admin
    module Stats
      class TasksController < Raif::Admin::ApplicationController
        def index
          @selected_period = params[:period] || "day"
          @time_range = get_time_range(@selected_period)

          @task_count = Raif::Task.where(created_at: @time_range).count

          @task_stats_by_type = Raif::Task.joins(:raif_model_completion)
            .where(created_at: @time_range)
            .group(:type)
            .pluck(
              "raif_tasks.type",
              "COUNT(raif_tasks.id)",
              "SUM(raif_model_completions.prompt_token_cost)",
              "SUM(raif_model_completions.output_token_cost)",
              "SUM(raif_model_completions.total_cost)"
            ).index_by(&:shift)
        end
      end
    end
  end
end
