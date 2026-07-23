# frozen_string_literal: true

module Raif
  module Admin
    class StatsController < Raif::Admin::ApplicationController
      def index
        @selected_period = params[:period] || "day"
        @time_range = get_time_range(@selected_period)

        # Cost aggregates read from Raif::InferenceCostEvent (not the
        # completions table) so they keep working after old completions are
        # culled. The time axis is incurred_at, which mirrors the completion's
        # created_at. Record counts still come from the records themselves.
        cost_events = Raif::InferenceCostEvent.where(incurred_at: @time_range)

        @model_completion_count = Raif::ModelCompletion.where(created_at: @time_range).count
        @model_completion_total_cost = cost_events.sum(:total_cost)
        @model_completion_input_token_cost = cost_events.sum(:prompt_token_cost)
        @model_completion_output_token_cost = cost_events.sum(:output_token_cost)

        @task_count = Raif::Task.where(created_at: @time_range).count
        task_events = cost_events.where(source_type: "Raif::Task")
        @task_total_cost = task_events.sum(:total_cost)
        @task_input_token_cost = task_events.sum(:prompt_token_cost)
        @task_output_token_cost = task_events.sum(:output_token_cost)

        @conversation_count = Raif::Conversation.where(created_at: @time_range).count

        @conversation_entry_count = Raif::ConversationEntry.where(created_at: @time_range).count
        conversation_entry_events = cost_events.where(source_type: "Raif::ConversationEntry")
        @conversation_entry_total_cost = conversation_entry_events.sum(:total_cost)
        @conversation_entry_input_token_cost = conversation_entry_events.sum(:prompt_token_cost)
        @conversation_entry_output_token_cost = conversation_entry_events.sum(:output_token_cost)

        @agent_count = Raif::Agent.where(created_at: @time_range).count
        agent_events = cost_events.where(source_type: "Raif::Agent")
        @agent_total_cost = agent_events.sum(:total_cost)
        @agent_input_token_cost = agent_events.sum(:prompt_token_cost)
        @agent_output_token_cost = agent_events.sum(:output_token_cost)

        @model_tool_invocation_count = Raif::ModelToolInvocation.where(created_at: @time_range).count
      end
    end
  end
end
