# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class AgentsController < BaseController
        def index
          @agent_types = Raif::Agent.distinct.pluck(:type).sort
          @selected_type = params[:agent_type] if params[:agent_type].present?
          @llm_model_keys = Raif::Agent.where(type: @selected_type).distinct.pluck(:llm_model_key).compact.sort if @selected_type.present?

          if @selected_type.present?
            agents = apply_filters(Raif::Agent.where(type: @selected_type)).order(created_at: :desc)
            @pagy, @agents = pagy(agents)
          end
        end

        def show
          @agent = Raif::Agent.find(params[:id])
          @comparison = build_prompt_comparison(@agent)
        end
      end
    end
  end
end
