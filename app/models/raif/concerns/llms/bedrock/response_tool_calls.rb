# frozen_string_literal: true

module Raif::Concerns::Llms::Bedrock::ResponseToolCalls
  extend ActiveSupport::Concern

  def extract_response_tool_calls(resp)
    # Get the message from the response object
    message = resp.output.message
    return if message.content.nil?

    # Find any tool_use blocks in the content array
    tool_uses = message.content.select do |content|
      content.respond_to?(:tool_use) && content.tool_use.present?
    end

    return if tool_uses.blank?

    tool_uses.map do |content|
      {
        "provider_tool_call_id" => content.tool_use.tool_use_id,
        "name" => content.tool_use.name,
        "arguments" => content.tool_use.input
      }
    end
  end
end
