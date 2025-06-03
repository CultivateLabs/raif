# frozen_string_literal: true

module Raif::Concerns::Llms::Bedrock::MessageFormatting
  extend ActiveSupport::Concern

  def format_string_message(content, role: nil)
    { "text" => content }
  end

  def format_model_image_input_message(image_input)
    if image_input.source_type == :url
      raise Raif::Errors::UnsupportedFeatureError, "AWS Bedrock does not support providing an image by URL"
    elsif image_input.source_type == :file_content
      # The AWS Bedrock SDK requires data sent as bytes (and doesn't support base64 like everyone else)
      # The ModelCompletion stores the messages as JSON though, so it can't be raw bytes (it will throw an encoding error).
      # We store the image data as base64 and then it will get converted to bytes in Raif::Llms::Bedrock#perform_model_completion!
      # before sending to AWS.
      {
        "image" => {
          "format" => format_for_content_type(image_input.content_type),
          "source" => {
            "tmp_base64_data" => image_input.base64_data
          }
        }
      }
    else
      raise Raif::Errors::InvalidModelImageInputError, "Invalid model image input source type: #{image_input.source_type}"
    end
  end

  def format_model_file_input_message(file_input)
    if file_input.source_type == :url
      raise Raif::Errors::UnsupportedFeatureError, "AWS Bedrock does not support providing a file by URL"
    elsif file_input.source_type == :file_content
      # The AWS Bedrock SDK requires data sent as bytes (and doesn't support base64 like everyone else)
      # The ModelCompletion stores the messages as JSON though, so it can't be raw bytes (it will throw an encoding error).
      # We store the image data as base64 and then it will get converted to bytes in Raif::Llms::Bedrock#perform_model_completion!
      # before sending to AWS.
      {
        "document" => {
          "format" => format_for_content_type(file_input.content_type),
          "name" => File.basename(file_input.filename, File.extname(file_input.filename)), # AWS requires a filename and it cannot include dots from the extension # rubocop:disable Layout/LineLength
          "source" => {
            "tmp_base64_data" => file_input.base64_data
          }
        }
      }
    else
      raise Raif::Errors::InvalidModelFileInputError, "Invalid model file input source type: #{file_input.source_type}"
    end
  end

  def format_for_content_type(content_type)
    {
      "image/png" => "png",
      "image/jpeg" => "jpeg",
      "image/gif" => "gif",
      "image/webp" => "webp",
      "application/pdf" => "pdf",
      "text/csv" => "csv",
      "application/msword" => "doc",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "docx",
      "application/vnd.ms-excel" => "xls",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "xlsx",
      "text/html" => "html",
      "text/plain" => "txt",
      "text/markdown" => "md"
    }[content_type]
  end
end
