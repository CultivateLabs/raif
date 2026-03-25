# frozen_string_literal: true

module Raif::Concerns::Llms::MessageFormatting
  extend ActiveSupport::Concern

  def format_messages(messages)
    messages.map do |message|
      if message.is_a?(Hash) && message["type"] == "tool_call"
        format_tool_call_message(message)
      elsif message.is_a?(Hash) && message["type"] == "tool_call_result"
        format_tool_call_result_message(message)
      else
        role = message["role"] || message[:role]
        {
          "role" => role,
          "content" => format_message_content(message["content"] || message[:content], role: role)
        }
      end
    end
  end

  # Content could be a string or an array.
  # If it's an array, it could contain Raif::ModelImageInput or Raif::ModelFileInput objects,
  # which need to be formatted according to each model provider's API.
  def format_message_content(content, role: nil)
    raise ArgumentError,
      "Message content must be an array or a string. Content was: #{content.inspect}" unless content.is_a?(Array) || content.is_a?(String)

    return [format_string_message(content, role: role)] if content.is_a?(String)

    content.map do |item|
      if item.is_a?(Raif::ModelImageInput)
        format_model_image_input_message(item)
      elsif item.is_a?(Raif::ModelFileInput)
        format_model_file_input_message(item)
      elsif item.is_a?(String)
        format_string_message(item, role: role)
      else
        item
      end
    end
  end

  def format_string_message(content, role: nil)
    { "type" => "text", "text" => content }
  end

  def consolidate_consecutive_role_messages(messages, content_key:)
    # Bedrock, Anthropic, and Google all model tool results as normal role-based
    # message content blocks. After formatting, a tool result can therefore be a
    # "user" message immediately followed by the next user turn. Those providers
    # expect alternating roles, so their adapters collapse adjacent same-role blocks.
    return messages if messages.size <= 1

    messages.each_with_object([]) do |message, consolidated|
      candidate = message.deep_dup
      previous_message = consolidated.last

      if mergeable_consecutive_role_messages?(previous_message, candidate, content_key:)
        previous_message[content_key] += candidate[content_key]
      else
        consolidated << candidate
      end
    end
  end

private

  def mergeable_consecutive_role_messages?(previous_message, message, content_key:)
    previous_message.is_a?(Hash) &&
      message.is_a?(Hash) &&
      previous_message["role"].present? &&
      previous_message["role"] == message["role"] &&
      previous_message[content_key].is_a?(Array) &&
      message[content_key].is_a?(Array)
  end

end
