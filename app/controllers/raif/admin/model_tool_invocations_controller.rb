# frozen_string_literal: true

module Raif
  module Admin
    class ModelToolInvocationsController < Raif::Admin::ApplicationController
      include Pagy::Backend

      def index
        @tool_types = Raif::ModelToolInvocation.distinct.pluck(:tool_type)
        @selected_type = params[:tool_types].present? && @tool_types.include?(params[:tool_types]) ? params[:tool_types] : "all"

        model_tool_invocations = Raif::ModelToolInvocation.newest_first
        model_tool_invocations = model_tool_invocations.where(tool_type: @selected_type) if @selected_type.present? && @selected_type != "all"

        @pagy, @model_tool_invocations = pagy(model_tool_invocations)
      end

      def show
        @model_tool_invocation = Raif::ModelToolInvocation.find(params[:id])
      end
    end
  end
end
