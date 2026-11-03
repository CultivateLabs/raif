# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiResponses::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    return if resp["output"].blank?

    tool_calls = []
    preceding_reasoning = []
    resp["output"].each do |output_item|
      if output_item["type"] == "reasoning"
        preceding_reasoning << output_item if output_item["encrypted_content"].present?
        next
      end

      unless output_item["type"] == "function_call"
        # OpenAI rejects a replayed reasoning item without the item that followed it.
        # Only function calls are replayed, so reasoning that led to anything else is dropped.
        preceding_reasoning = []
        next
      end

      tool_call = {
        "provider_tool_call_id" => output_item["call_id"],
        "name" => output_item["name"],
        "arguments" => begin
          JSON.parse(output_item["arguments"])
        rescue JSON::ParserError
          output_item["arguments"]
        end
      }
      tool_call["provider_metadata"] = { "reasoning_items" => preceding_reasoning } if preceding_reasoning.any?
      preceding_reasoning = []

      tool_calls << tool_call
    end

    tool_calls.any? ? tool_calls : nil
  end
end
