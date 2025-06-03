# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAiResponses::MessageFormatting
  extend ActiveSupport::Concern

  def format_string_message(content, role: nil)
    if role == "assistant"
      { "type" => "output_text", "text" => content }
    else
      { "type" => "input_text", "text" => content }
    end
  end

  def format_model_image_input_message(image_input)
    if image_input.source_type == :url
      {
        "type" => "input_image",
        "image_url" => image_input.url
      }
    elsif image_input.source_type == :file_content
      {
        "type" => "input_image",
        "image_url" => "data:#{image_input.content_type};base64,#{image_input.base64_data}"
      }
    else
      raise Raif::Errors::InvalidModelImageInputError, "Invalid model image input source type: #{image_input.source_type}"
    end
  end

  def format_model_file_input_message(file_input)
    if file_input.source_type == :url
      raise Raif::Errors::UnsupportedFeatureError, "#{self.class.name} does not support providing a file by URL"
    elsif file_input.source_type == :file_content
      {
        "type" => "input_file",
        "filename" => file_input.filename,
        "file_data" => "data:#{file_input.content_type};base64,#{file_input.base64_data}"
      }
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid model image input source type: #{file_input.source_type}"
    end
  end
end
