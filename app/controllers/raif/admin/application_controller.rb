# frozen_string_literal: true

module Raif
  module Admin
    class ApplicationController < Raif::ApplicationController
      include Pagy::Backend

      layout "raif/admin"

    private

      def authorize_raif_action
        unless instance_exec(&Raif.config.authorize_admin_controller_action)
          raise Raif::Errors::ActionNotAuthorizedError, "Admin action not authorized"
        end
      end

      def get_time_range(period)
        case period
        when "day"
          24.hours.ago..Time.current
        when "week"
          1.week.ago..Time.current
        when "month"
          1.month.ago..Time.current
        when "all"
          Time.at(0)..Time.current
        else
          24.hours.ago..Time.current
        end
      end

      helper_method :conversation_message_header_class
      def conversation_message_header_class(message)
        message_type = message["type"] || message["role"]

        case message_type
        when "user"
          "text-primary"
        when "tool_call"
          "text-warning"
        when "tool_call_result"
          "text-success"
        else
          "text-success"
        end
      end
    end
  end
end
