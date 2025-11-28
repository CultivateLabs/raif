# frozen_string_literal: true

module Raif::Concerns::Llms::Anthropic::MessageFormatting
  extend ActiveSupport::Concern

  def format_model_image_input_message(image_input)
    if image_input.source_type == :url
      {
        "type" => "image",
        "source" => {
          "type" => "url",
          "url" => image_input.url
        }
      }
    elsif image_input.source_type == :file_content
      {
        "type" => "image",
        "source" => {
          "type" => "base64",
          "media_type" => image_input.content_type,
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
        "type" => "document",
        "source" => {
          "type" => "url",
          "url" => file_input.url
        }
      }
    elsif file_input.source_type == :file_content
      {
        "type" => "document",
        "source" => {
          "type" => "base64",
          "media_type" => file_input.content_type,
          "data" => file_input.base64_data
        }
      }
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid model file input source type: #{file_input.source_type}"
    end
  end

  def format_tool_call_message(tool_call)
    content_array = []
    content_array << format_string_message(tool_call["assistant_message"]) if tool_call["assistant_message"].present?

    content_array << {
      "type" => "tool_use",
      "id" => tool_call["provider_tool_call_id"],
      "name" => tool_call["name"],
      "input" => tool_call["arguments"]
    }

    {
      "role" => "assistant",
      "content" => content_array
    }
  end

  def format_tool_call_result_message(tool_call_result)
    {
      "role" => "user",
      "content" => [{
        "type" => "tool_result",
        "tool_use_id" => tool_call_result["provider_tool_call_id"],
        "content" => tool_call_result["result"].is_a?(String) ? tool_call_result["result"] : JSON.generate(tool_call_result["result"])
      }]
    }
  end
end
