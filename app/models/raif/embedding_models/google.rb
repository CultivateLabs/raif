# frozen_string_literal: true

class Raif::EmbeddingModels::Google < Raif::EmbeddingModel
  def generate_embedding!(input, dimensions: nil)
    unless input.is_a?(String)
      raise ArgumentError, "Raif::EmbeddingModels::Google#generate_embedding! input must be a string"
    end

    response = connection.post("models/#{api_name}:embedContent") do |req|
      req.body = build_request_parameters(input, dimensions:)
    end

    response.body.dig("embedding", "values")
  end

private

  def build_request_parameters(input, dimensions: nil)
    params = {
      content: {
        parts: [{ text: input }]
      }
    }

    params[:outputDimensionality] = dimensions if dimensions.present?
    params
  end

  def connection
    @connection ||= Faraday.new(url: "https://generativelanguage.googleapis.com/v1beta", request: Raif.default_request_options) do |f|
      f.headers["x-goog-api-key"] = Raif.config.google_api_key
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end
end
