# frozen_string_literal: true

class Raif::Llms::OpenAiBase < Raif::Llm
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation

  def perform_model_completion!(model_completion, &block)
    if supports_temperature?
      model_completion.temperature ||= default_temperature
    else
      Raif.logger.warn "Temperature is not supported for #{api_name}. Ignoring temperature parameter."
      model_completion.temperature = nil
    end

    parameters = build_request_parameters(model_completion)
    model_completion.response_format_parameter = parameters.dig(:text, :format, :type)

    response = connection.post(api_path) do |req|
      req.body = parameters
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

private

  def connection
    @connection ||= Faraday.new(url: "https://api.openai.com/v1") do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

  def format_system_prompt(model_completion)
    formatted_system_prompt = model_completion.system_prompt.to_s.strip

    # If the response format is JSON, we need to include "as json" in the system prompt.
    # OpenAI requires this and will throw an error if it's not included.
    if model_completion.response_format_json?
      # Ensure system prompt ends with a period if not empty
      if formatted_system_prompt.present? && !formatted_system_prompt.end_with?(".", "?", "!")
        formatted_system_prompt += "."
      end
      formatted_system_prompt += " Return your response as JSON."
      formatted_system_prompt.strip!
    end

    formatted_system_prompt
  end

  def supports_structured_outputs?
    # Not all OpenAI models support structured outputs:
    # https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#supported-models
    provider_settings.key?(:supports_structured_outputs) ? provider_settings[:supports_structured_outputs] : true
  end

  def supports_temperature?
    provider_settings.key?(:supports_temperature) ? provider_settings[:supports_temperature] : true
  end

end
