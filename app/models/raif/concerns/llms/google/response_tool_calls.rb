# frozen_string_literal: true

module Raif::Concerns::Llms::Google::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    parts = resp&.dig("candidates", 0, "content", "parts")
    return if parts.blank?

    # Find any functionCall parts
    function_calls = parts.select { |part| part.key?("functionCall") }

    return if function_calls.blank?

    function_calls.map do |part|
      function_call = part["functionCall"]
      {
        # Google doesn't provide a unique ID for function calls, so we generate one
        "provider_tool_call_id" => SecureRandom.uuid,
        "name" => function_call["name"],
        "arguments" => function_call["args"]
      }
    end
  end
end
