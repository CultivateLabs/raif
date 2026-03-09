# frozen_string_literal: true

module Raif
  module ApplicationHelper
    include Pagy::Frontend

    def format_task_response(task)
      if task.response_format_json? && task.raw_response.present?
        JSON.pretty_generate(JSON.parse(task.raw_response))
      else
        task.raw_response
      end
    rescue JSON::ParserError
      task.raw_response
    end
  end
end
