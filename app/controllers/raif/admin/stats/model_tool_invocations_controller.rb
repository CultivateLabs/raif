# frozen_string_literal: true

module Raif
  module Admin
    module Stats
      class ModelToolInvocationsController < Raif::Admin::ApplicationController
        def index
          @selected_period = params[:period] || "day"
          @time_range = get_time_range(@selected_period)

          @model_tool_invocation_count = Raif::ModelToolInvocation.where(created_at: @time_range).count

          @model_tool_invocation_stats_by_type = Raif::ModelToolInvocation
            .where(created_at: @time_range)
            .group(:tool_type)
            .count
        end
      end
    end
  end
end