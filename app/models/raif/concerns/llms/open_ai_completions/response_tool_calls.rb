# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiCompletions::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    tool_calls = resp.dig("choices", 0, "message", "tool_calls")
    return if tool_calls.blank?

    tool_calls.map do |tool_call|
      {
        "id" => tool_call["id"],
        "name" => tool_call["function"]["name"],
        "arguments" => JSON.parse(tool_call["function"]["arguments"])
      }
    end
  end
end
