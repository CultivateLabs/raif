# frozen_string_literal: true

module Raif::Concerns::Llms::Anthropic::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    return if resp&.dig("content").nil?

    # Find any tool_use content blocks
    tool_uses = resp&.dig("content")&.select do |content|
      content["type"] == "tool_use"
    end

    return if tool_uses.blank?

    tool_uses.map do |tool_use|
      {
        "provider_tool_call_id" => tool_use["id"],
        "name" => tool_use["name"],
        "arguments" => tool_use["input"],
      }
    end
  end
end
