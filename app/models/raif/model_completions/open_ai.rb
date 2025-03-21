# frozen_string_literal: true

class Raif::ModelCompletions::OpenAi < Raif::ModelCompletion
  def prompt_model_for_response!
    self.temperature ||= default_temperature

    parameters = build_chat_parameters
    client = OpenAI::Client.new
    resp = client.chat(parameters: parameters)

    self.raw_response = resp.dig("choices", 0, "message", "content")
    self.completion_tokens = resp["usage"]["completion_tokens"]
    self.prompt_tokens = resp["usage"]["prompt_tokens"]
    self.total_tokens = resp["usage"]["total_tokens"]

    save!
  end

private

  def build_chat_parameters
    formatted_system_prompt = system_prompt.to_s.strip

    # Ensure system prompt ends with a period if not empty
    unless formatted_system_prompt.empty? || formatted_system_prompt.end_with?(".", "?", "!")
      formatted_system_prompt += "."
    end

    # If the response format is JSON, we need to include "as json" in the system prompt.
    # OpenAI requires this and will throw an error if it's not included.
    if response_format_json? && !formatted_system_prompt.empty?
      formatted_system_prompt += " Return your response as json."
    end

    messages_with_system = if !formatted_system_prompt.empty?
      [{ "role" => "system", "content" => formatted_system_prompt }] + messages
    else
      messages
    end

    parameters = {
      model: model_api_name,
      messages: messages_with_system,
      temperature: temperature.to_f
    }

    # Add response format if needed
    response_format = determine_response_format
    parameters[:response_format] = response_format if response_format

    parameters
  end

  def determine_response_format
    # Only configure response format for JSON outputs
    return unless response_format_json?

    schema = if source&.respond_to?(:json_response_schema)
      # Use the source's schema if available
      source.json_response_schema
    else
      default_json_response_schema
    end

    if supports_structured_outputs?
      {
        "type" => "json_schema",
        "json_schema" =>
        {
          name: "json_response",
          schema: schema,
          strict: true
        }
      }
    else
      # Default JSON mode for OpenAI models that don't support structured outputs
      { "type" => "json_object" }
    end
  end

  def supports_structured_outputs?
    # Not all OpenAI models support structured outputs:
    # https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#supported-models
    %w[gpt-4o-mini gpt-4o-mini-2024-07-18 gpt-4o gpt-4o-2024-08-06 gpt-4o-2024-11-20].include?(model_api_name)
  end
end
