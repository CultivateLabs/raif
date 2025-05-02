# frozen_string_literal: true

module Raif::Concerns::Llms::MessageFormatting
  extend ActiveSupport::Concern

  def format_messages(messages)
    messages.map do |message|
      {
        "role" => message["role"] || message[:role],
        "content" => format_message_content(message["content"] || message[:content])
      }
    end
  end

  # Content could be a string or an array.
  # If it's an array, it could contain Raif::ModelImageInput or Raif::ModelFileInput objects,
  # which need to be formatted according to each model provider's API.
  def format_message_content(content)
    raise ArgumentError,
      "Message content must be an array or a string. Content was: #{content.inspect}" unless content.is_a?(Array) || content.is_a?(String)

    return [format_string_message(content)] if content.is_a?(String)

    content.map do |item|
      if item.is_a?(Raif::ModelImageInput)
        format_model_image_input_message(item)
      elsif item.is_a?(Raif::ModelFileInput)
        format_model_file_input_message(item)
      elsif item.is_a?(String)
        format_string_message(item)
      else
        item
      end
    end
  end

  def format_string_message(content)
    { "type" => "text", "text" => content }
  end

end
