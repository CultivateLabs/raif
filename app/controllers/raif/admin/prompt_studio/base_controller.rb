# frozen_string_literal: true

module Raif
  module Admin
    module PromptStudio
      class BaseController < Raif::Admin::ApplicationController
        include Pagy::Backend

      private

        def build_prompt_comparison(record)
          Raif::PromptStudioComparisonBuilder.build(record)
        end

        def apply_filters(scope)
          scope = scope.where("#{scope.table_name}.created_at >= ?", Time.zone.parse(params[:created_after])) if params[:created_after].present?
          scope = scope.where("#{scope.table_name}.created_at <= ?", Time.zone.parse(params[:created_before]).end_of_day) if params[:created_before].present?
          scope = scope.where(llm_model_key: params[:llm_model_key]) if params[:llm_model_key].present?
          scope
        end

        helper_method :prompt_studio_runs_enabled?
        def prompt_studio_runs_enabled?
          Raif.config.prompt_studio_runs_enabled
        end
      end
    end
  end
end
