# frozen_string_literal: true

class Raif::Llms::OpenAiCompletions < Raif::Llms::OpenAiBase
  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::Streaming

  def perform_model_completion!(model_completion, &block)
    model_completion.temperature ||= default_temperature
    parameters = build_request_parameters(model_completion)
    model_completion.response_format_parameter = parameters.dig(:response_format, :type)

    response = connection.post("chat/completions") do |req|
      req.body = parameters
      req.options.on_data = streaming_chunk_handler(model_completion, &block) if model_completion.stream_response?
    end

    unless model_completion.stream_response?
      update_model_completion(model_completion, response.body)
    end

    model_completion
  end

private

  def update_model_completion(model_completion, response_json)
    model_completion.update!(
      response_id: response_json["id"],
      response_tool_calls: extract_response_tool_calls(response_json),
      raw_response: response_json.dig("choices", 0, "message", "content"),
      response_array: response_json["choices"],
      completion_tokens: response_json.dig("usage", "completion_tokens"),
      prompt_tokens: response_json.dig("usage", "prompt_tokens"),
      total_tokens: response_json.dig("usage", "total_tokens")
    )
  end

  def extract_response_tool_calls(resp)
    return if resp.dig("choices", 0, "message", "tool_calls").blank?

    resp.dig("choices", 0, "message", "tool_calls").map do |tool_call|
      {
        "name" => tool_call["function"]["name"],
        "arguments" => JSON.parse(tool_call["function"]["arguments"])
      }
    end
  end

  def build_request_parameters(model_completion)
    formatted_system_prompt = format_system_prompt(model_completion)

    messages = model_completion.messages
    messages_with_system = if formatted_system_prompt.blank?
      messages
    else
      [{ "role" => "system", "content" => formatted_system_prompt }] + messages
    end

    parameters = {
      model: api_name,
      messages: messages_with_system,
      temperature: model_completion.temperature.to_f
    }

    # If the LLM supports native tool use and there are available tools, add them to the parameters
    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      parameters[:tools] = tools unless tools.blank?
    end

    if model_completion.stream_response?
      parameters[:stream] = true
      # Ask for usage stats in the last chunk
      parameters[:stream_options] = { include_usage: true }
    end

    # Add response format if needed
    response_format = determine_response_format(model_completion)
    parameters[:response_format] = response_format if response_format

    parameters
  end

  def determine_response_format(model_completion)
    # Only configure response format for JSON outputs
    return unless model_completion.response_format_json?

    if model_completion.json_response_schema.present? && supports_structured_outputs?
      validate_json_schema!(model_completion.json_response_schema)

      {
        type: "json_schema",
        json_schema: {
          name: "json_response_schema",
          strict: true,
          schema: model_completion.json_response_schema
        }
      }
    else
      # Default JSON mode for OpenAI models that don't support structured outputs or no schema is provided
      { type: "json_object" }
    end
  end

end
