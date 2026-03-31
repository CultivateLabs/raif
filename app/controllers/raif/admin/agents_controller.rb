# frozen_string_literal: true

module Raif
  module Admin
    class AgentsController < Raif::Admin::ApplicationController
      include Pagy::Backend

      def index
        @agent_types = Raif::Agent.distinct.pluck(:type)
        @selected_type = params[:agent_type].present? ? params[:agent_type] : "all"

        @selected_status = params[:status].present? ? params[:status].to_sym : :all

        @selected_llm_model_key = params[:llm_model_key].presence
        @llm_model_keys = Raif::Agent.distinct.pluck(:llm_model_key).sort

        agents = Raif::Agent.order(created_at: :desc)
        agents = agents.where(type: @selected_type) if @selected_type.present? && @selected_type != "all"

        if @selected_status.present? && @selected_status != :all
          case @selected_status
          when :completed
            agents = agents.completed
          when :failed
            agents = agents.failed
          when :running
            agents = agents.started.where(completed_at: nil, failed_at: nil)
          when :pending
            agents = agents.where(started_at: nil)
          end
        end

        agents = agents.where(llm_model_key: @selected_llm_model_key) if @selected_llm_model_key.present?

        @pagy, @agents = pagy(agents)
      end

      def show
        @agent = Raif::Agent.find(params[:id])
      end
    end
  end
end
