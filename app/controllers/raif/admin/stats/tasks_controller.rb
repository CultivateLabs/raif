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

          # Aggregates read from Raif::InferenceCostEvent (not the completions
          # table) so they keep working after old completions are culled. The
          # time axis is incurred_at (the completion's created_at) rather than
          # the task's created_at, and the count is a completion count (1:1
          # with tasks).
          events = Raif::InferenceCostEvent.where(source_type: "Raif::Task", incurred_at: @time_range)

          group_columns = @show_model_breakdown ? [:source_class_name, :llm_model_key] : [:source_class_name]
          select_columns = ["source_class_name"]
          select_columns << "llm_model_key" if @show_model_breakdown
          select_columns << Arel.sql("COUNT(*)")
          select_columns << Arel.sql("SUM(prompt_token_cost)")
          select_columns << Arel.sql("SUM(output_token_cost)")
          select_columns << Arel.sql("SUM(total_cost)")

          @task_stats_by_type = events
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
