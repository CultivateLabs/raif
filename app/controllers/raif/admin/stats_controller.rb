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

        tasks = Raif::Task.where(created_at: @time_range)
        @task_count = tasks.count
        @task_total_cost = Raif::ModelCompletion.where(source_type: "Raif::Task", source_id: tasks.select(:id)).sum(:total_cost)
        @task_input_token_cost = Raif::ModelCompletion.where(source_type: "Raif::Task", source_id: tasks.select(:id)).sum(:prompt_token_cost)
        @task_output_token_cost = Raif::ModelCompletion.where(source_type: "Raif::Task", source_id: tasks.select(:id)).sum(:output_token_cost)

        conversations = Raif::Conversation.where(created_at: @time_range)
        @conversation_count = conversations.count
        conversation_entry_ids = Raif::ConversationEntry.where(raif_conversation_id: conversations.select(:id)).select(:id)
        @conversation_total_cost = Raif::ModelCompletion.where(
          source_type: "Raif::ConversationEntry",
          source_id: conversation_entry_ids
        ).sum(:total_cost)
        @conversation_input_token_cost = Raif::ModelCompletion.where(
          source_type: "Raif::ConversationEntry",
          source_id: conversation_entry_ids
        ).sum(:prompt_token_cost)
        @conversation_output_token_cost = Raif::ModelCompletion.where(
          source_type: "Raif::ConversationEntry",
          source_id: conversation_entry_ids
        ).sum(:output_token_cost)

        @conversation_entry_count = Raif::ConversationEntry.where(created_at: @time_range).count

        agents = Raif::Agent.where(created_at: @time_range)
        @agent_count = agents.count
        @agent_total_cost = Raif::ModelCompletion.where(source_type: "Raif::Agent", source_id: agents.select(:id)).sum(:total_cost)
        @agent_input_token_cost = Raif::ModelCompletion.where(source_type: "Raif::Agent", source_id: agents.select(:id)).sum(:prompt_token_cost)
        @agent_output_token_cost = Raif::ModelCompletion.where(source_type: "Raif::Agent", source_id: agents.select(:id)).sum(:output_token_cost)
        @model_tool_invocation_count = Raif::ModelToolInvocation.where(created_at: @time_range).count
      end
    end
  end
end
