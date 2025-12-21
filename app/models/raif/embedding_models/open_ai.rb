# frozen_string_literal: true

class Raif::EmbeddingModels::OpenAi < Raif::EmbeddingModel
  def generate_embedding!(input, dimensions: nil)
    unless input.is_a?(String) || input.is_a?(Array)
      raise ArgumentError, "Raif::EmbeddingModels::OpenAi#generate_embedding! input must be a string or an array of strings"
    end

    response = connection.post("embeddings") do |req|
      req.body = build_request_parameters(input, dimensions:)
    end

    if input.is_a?(String)
      response.body["data"][0]["embedding"]
    else
      response.body["data"].map{|v| v["embedding"] }
    end
  end

private

  def build_request_parameters(input, dimensions: nil)
    params = {
      model: api_name,
      input: input
    }

    params[:dimensions] = dimensions if dimensions.present?
    params
  end

  def connection
    @connection ||= Faraday.new(url: "https://api.openai.com/v1", request: Raif.default_request_options) do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end
end
