# frozen_string_literal: true

module Raif
  module Admin
    class StatsController < Raif::Admin::ApplicationController
      def index
        @selected_period = params[:period] || "day"
        @time_range = get_time_range(@selected_period)

        model_completions = Raif::ModelCompletion.where(created_at: @time_range)

        @model_completion_count = model_completions.count
        @model_completion_total_cost = model_completions.sum(:total_cost)
        @model_completion_input_token_cost = model_completions.sum(:prompt_token_cost)
        @model_completion_output_token_cost = model_completions.sum(:output_token_cost)

        @task_count = Raif::Task.where(created_at: @time_range).count
        @conversation_count = Raif::Conversation.where(created_at: @time_range).count
        @conversation_entry_count = Raif::ConversationEntry.where(created_at: @time_range).count
        @agent_count = Raif::Agent.where(created_at: @time_range).count
        @model_tool_invocation_count = Raif::ModelToolInvocation.where(created_at: @time_range).count
      end
    end
  end
end
