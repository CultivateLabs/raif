# frozen_string_literal: true

class Raif::EmbeddingModels::Bedrock < Raif::EmbeddingModel

  def generate_embedding!(input, dimensions: nil)
    unless input.is_a?(String)
      raise ArgumentError, "Raif::EmbeddingModels::Bedrock#generate_embedding! input must be a string"
    end

    params = build_request_parameters(input, dimensions:)
    response = bedrock_client.invoke_model(params)

    response_body = JSON.parse(response.body.read)
    response_body["embedding"]
  rescue Aws::BedrockRuntime::Errors::ServiceError => e
    raise "Bedrock API error: #{e.message}"
  end

private

  def build_request_parameters(input, dimensions: nil)
    body_params = { inputText: input }
    body_params[:dimensions] = dimensions if dimensions.present?

    {
      model_id: api_name,
      body: body_params.to_json
    }
  end

  def bedrock_client
    @bedrock_client ||= begin
      client_options = {
        region: Raif.config.aws_bedrock_region
      }

      client_options[:http_read_timeout] = Raif.config.request_read_timeout if Raif.config.request_read_timeout
      client_options[:http_open_timeout] = Raif.config.request_open_timeout if Raif.config.request_open_timeout

      Aws::BedrockRuntime::Client.new(client_options)
    end
  end
end
