# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiResponses::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    return if resp["output"].blank?

    tool_calls = []
    resp["output"].each do |output_item|
      next unless output_item["type"] == "function_call"

      tool_calls << {
        "provider_tool_call_id" => output_item["call_id"],
        "name" => output_item["name"],
        "arguments" => begin
          JSON.parse(output_item["arguments"])
        rescue JSON::ParserError
          output_item["arguments"]
        end
      }
    end

    tool_calls.any? ? tool_calls : nil
  end
end
