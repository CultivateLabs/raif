# frozen_string_literal: true

class Raif::Llms::OpenAiBase < Raif::Llm
  include Raif::Concerns::Llms::OpenAi::JsonSchemaValidation

  def connection
    @connection ||= Faraday.new(url: "https://api.openai.com/v1") do |f|
      f.headers["Authorization"] = "Bearer #{Raif.config.open_ai_api_key}"
      f.request :json
      f.response :json
      f.response :raise_error
    end
  end

private

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

end
