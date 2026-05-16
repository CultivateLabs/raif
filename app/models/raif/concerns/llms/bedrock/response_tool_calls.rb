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
        "arguments" => parse_tool_use_input(content.tool_use.input)
      }
    end
  end

private

  # Defensively guard against tool_use.input arriving as a String rather than
  # a Hash. The AWS SDK normally deserializes Bedrock's Document-typed tool
  # input to a Hash (verified against Claude, Nova, and gpt-oss-120b on the
  # non-streaming Converse API), but if a model/error path ever surfaces a
  # raw JSON string here, mirror the streaming handler's behavior: parse
  # when possible, otherwise leave the raw String so the downstream validator
  # can reject it and trigger a repair loop.
  def parse_tool_use_input(input)
    return input unless input.is_a?(String)

    JSON.parse(input)
  rescue JSON::ParserError
    input
  end
end
