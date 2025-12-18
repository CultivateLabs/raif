# frozen_string_literal: true

module Raif::Concerns::Llms::Google::MessageFormatting
  extend ActiveSupport::Concern

  # Override the base format_messages to use Google's message format
  def format_messages(messages)
    messages.map do |message|
      if message.is_a?(Hash) && message["type"] == "tool_call"
        format_tool_call_message(message)
      elsif message.is_a?(Hash) && message["type"] == "tool_call_result"
        format_tool_call_result_message(message)
      else
        role = message["role"] || message[:role]
        # Google uses "model" instead of "assistant"
        google_role = role == "assistant" ? "model" : role
        {
          "role" => google_role,
          "parts" => format_message_content(message["content"] || message[:content], role: role)
        }
      end
    end
  end

  def format_string_message(content, role: nil)
    { "text" => content }
  end

  def format_model_image_input_message(image_input)
    if image_input.source_type == :url
      {
        "fileData" => {
          "mimeType" => image_input.content_type,
          "fileUri" => image_input.url
        }
      }
    elsif image_input.source_type == :file_content
      {
        "inlineData" => {
          "mimeType" => image_input.content_type,
          "data" => image_input.base64_data
        }
      }
    else
      raise Raif::Errors::InvalidModelImageInputError, "Invalid model image input source type: #{image_input.source_type}"
    end
  end

  def format_model_file_input_message(file_input)
    if file_input.source_type == :url
      {
        "fileData" => {
          "mimeType" => file_input.content_type,
          "fileUri" => file_input.url
        }
      }
    elsif file_input.source_type == :file_content
      {
        "inlineData" => {
          "mimeType" => file_input.content_type,
          "data" => file_input.base64_data
        }
      }
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid model file input source type: #{file_input.source_type}"
    end
  end

  def format_tool_call_message(tool_call)
    parts = []

    if tool_call["assistant_message"].present?
      parts << format_string_message(tool_call["assistant_message"])
    end

    parts << {
      "functionCall" => {
        "name" => tool_call["name"],
        "args" => tool_call["arguments"]
      }
    }

    {
      "role" => "model",
      "parts" => parts
    }
  end

  def format_tool_call_result_message(tool_call_result)
    result = tool_call_result["result"]
    response_content = result.is_a?(String) ? { "output" => result } : result

    {
      "role" => "user",
      "parts" => [{
        "functionResponse" => {
          "name" => tool_call_result["name"],
          "response" => response_content
        }
      }]
    }
  end
end
