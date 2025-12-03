# frozen_string_literal: true

class AgentsController < ApplicationController

  def index
  end

  def create
    agent = Raif::Agents::NativeToolCallingAgent.new(
      task: params[:task],
      available_model_tools: [Raif::ModelTools::WikipediaSearch, Raif::ModelTools::FetchUrl],
      creator: current_user
    )

    agent.run! do |conversation_history_entry|
      Turbo::StreamsChannel.broadcast_append_to(
        :agents,
        target: "agent-progress",
        partial: "agents/conversation_history_entry",
        locals: { agent: agent, conversation_history_entry: conversation_history_entry }
      )
    end

    head :no_content
  end
end
