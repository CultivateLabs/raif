# frozen_string_literal: true

module Raif::Concerns::Llms::OpenAi::MessageFormatting
  extend ActiveSupport::Concern

  def format_model_image_input_message(image_input)
    if image_input.source_type == :url
      {
        "type" => "image_url",
        "image_url" => { "url" => image_input.url }
      }
    elsif image_input.source_type == :file_content
      {
        "type" => "image_url",
        "image_url" => {
          "url" => "data:#{image_input.content_type};base64,#{image_input.base64_data}"
        }
      }
    else
      raise Raif::Errors::InvalidModelImageInputError, "Invalid model image input source type: #{image_input.source_type}"
    end
  end

  def format_model_file_input_message(file_input)
    if file_input.source_type == :url
      raise Raif::Errors::UnsupportedFeatureError, "#{self.class.name} does not support providing a file by URL"
    elsif file_input.source_type == :file_content
      file_params = {
        "filename" => file_input.filename,
        "file_data" => "data:#{file_input.content_type};base64,#{file_input.base64_data}"
      }.compact

      {
        "type" => "file",
        "file" => file_params
      }
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid model image input source type: #{file_input.source_type}"
    end
  end
end
