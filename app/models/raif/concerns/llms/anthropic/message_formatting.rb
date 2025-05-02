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
end
