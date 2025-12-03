# frozen_string_literal: true

class Raif::Llms::OpenAiCompletions < Raif::Llms::OpenAiBase
  include Raif::Concerns::Llms::OpenAiCompletions::MessageFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ToolFormatting
  include Raif::Concerns::Llms::OpenAiCompletions::ResponseToolCalls

private

  def api_path
    "chat/completions"
  end

  def streaming_response_type
    Raif::StreamingResponses::OpenAiCompletions
  end

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
      messages: messages_with_system
    }

    if supports_temperature?
      parameters[:temperature] = model_completion.temperature.to_f
    end

    # If the LLM supports native tool use and there are available tools, add them to the parameters
    if supports_native_tool_use?
      tools = build_tools_parameter(model_completion)
      parameters[:tools] = tools unless tools.blank?

      if model_completion.tool_choice.present?
        tool_klass = model_completion.tool_choice.constantize
        parameters[:tool_choice] = build_forced_tool_choice(tool_klass.tool_name)
      end
    end

    if model_completion.stream_response?
      parameters[:stream] = true
      # Ask for usage stats in the last chunk
      parameters[:stream_options] = { include_usage: true }
    end

    # Add response format if needed
    response_format = determine_response_format(model_completion)
    parameters[:response_format] = response_format if response_format
    model_completion.response_format_parameter = response_format[:type] if response_format

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
