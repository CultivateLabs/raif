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
    @bedrock_client ||= Aws::BedrockRuntime::Client.new(region: Raif.config.aws_bedrock_region)
  end
end
