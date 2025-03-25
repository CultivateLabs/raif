# frozen_string_literal: true

class Raif::Llms::OpenAi < Raif::Llm

  def perform_model_completion!(model_completion)
    model_completion.temperature ||= default_temperature
    parameters = build_chat_parameters(model_completion)

    client = OpenAI::Client.new
    resp = client.chat(parameters: parameters)

    model_completion.update!(
      response_tool_calls: extract_response_tool_calls(resp),
      raw_response: resp.dig("choices", 0, "message", "content"),
      completion_tokens: resp["usage"]["completion_tokens"],
      prompt_tokens: resp["usage"]["prompt_tokens"],
      total_tokens: resp["usage"]["total_tokens"],
      response_format_parameter: parameters.dig(:response_format, :type)
    )

    model_completion
  end

  def validate_json_schema!(schema)
    return if schema.blank?

    errors = []

    # Check if schema is present
    if schema.blank?
      errors << "JSON schema must include a 'schema' property"
    else
      # Check root object type
      if schema[:type] != "object" && !schema.key?(:properties)
        errors << "Root schema must be of type 'object' with 'properties'"
      end

      # Check all objects in the schema recursively
      validate_object_properties(schema, errors)

      # Check properties count (max 100 total)
      validate_properties_count(schema, errors)

      # Check nesting depth (max 5 levels)
      validate_nesting_depth(schema, errors)

      # Check for unsupported anyOf at root level
      if schema[:anyOf].present? && schema[:properties].blank?
        errors << "Root objects cannot be of type 'anyOf'"
      end
    end

    # Raise error if any validation issues found
    if errors.any?
      error_message = "Invalid JSON schema for OpenAI structured outputs: #{errors.join("; ")}"
      raise Raif::Errors::OpenAi::JsonSchemaError, error_message
    else
      true
    end
  end

private

  def extract_response_tool_calls(resp)
    return if resp.dig("choices", 0, "message", "tool_calls").blank?

    resp.dig("choices", 0, "message", "tool_calls").map do |tool_call|
      {
        name: tool_call["function"]["name"],
        arguments: JSON.parse(tool_call["function"]["arguments"])
      }
    end
  end

  def build_chat_parameters(model_completion)
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

    messages = model_completion.messages
    messages_with_system = if !formatted_system_prompt.empty?
      [{ "role" => "system", "content" => formatted_system_prompt }] + messages
    else
      messages
    end

    parameters = {
      model: api_name,
      messages: messages_with_system,
      temperature: model_completion.temperature.to_f
    }

    # If the LLM supports native tool use and there are available tools, add them to the parameters
    if supports_native_tool_use? && model_completion.available_model_tools.any?
      parameters[:tools] = model_completion.available_model_tools_map.map do |_tool_name, tool|
        validate_json_schema!(tool.tool_arguments_schema)

        {
          type: "function",
          function: {
            name: tool.tool_name,
            description: tool.tool_description,
            parameters: tool.tool_arguments_schema
          }
        }
      end
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

  def supports_structured_outputs?
    # Not all OpenAI models support structured outputs:
    # https://platform.openai.com/docs/guides/structured-outputs?api-mode=chat#supported-models
    provider_settings[:supports_structured_outputs]
  end

  def validate_object_properties(schema, errors)
    return unless schema.is_a?(Hash)

    # Check if the current schema is an object and validate additionalProperties and required fields
    if schema[:type] == "object"
      if schema[:additionalProperties] != false
        errors << "All objects must have 'additionalProperties' set to false"
      end

      # Check that all properties are required
      if schema[:properties].is_a?(Hash) && schema[:properties].any?
        property_keys = schema[:properties].keys
        required_fields = schema[:required] || []

        if required_fields.sort != property_keys.map(&:to_s).sort
          errors << "All object properties must be listed in the 'required' array"
        end
      end
    end

    # Check if the current schema is an object and validate additionalProperties
    if schema[:type] == "object"
      if schema[:additionalProperties] != false
        errors << "All objects must have 'additionalProperties' set to false"
      end

      # Check properties of the object recursively
      if schema[:properties].is_a?(Hash)
        schema[:properties].each_value do |property|
          validate_object_properties(property, errors)
        end
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      validate_object_properties(schema[:items], errors)
    end

    # Check anyOf
    if schema[:anyOf].is_a?(Array)
      schema[:anyOf].each do |option|
        validate_object_properties(option, errors)
      end
    end
  end

  def validate_properties_count(schema, errors, count = 0)
    return count unless schema.is_a?(Hash)

    if schema[:properties].is_a?(Hash)
      count += schema[:properties].size

      if count > 100
        errors << "Schema exceeds maximum of 100 total object properties"
        return count
      end

      # Check nested properties
      schema[:properties].each_value do |property|
        count = validate_properties_count(property, errors, count)
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      count = validate_properties_count(schema[:items], errors, count)
    end

    count
  end

  def validate_nesting_depth(schema, errors, depth = 1)
    return unless schema.is_a?(Hash)

    if depth > 5
      errors << "Schema exceeds maximum nesting depth of 5 levels"
      return
    end

    if schema[:properties].is_a?(Hash)
      schema[:properties].each_value do |property|
        validate_nesting_depth(property, errors, depth + 1)
      end
    end

    # Check array items
    if schema[:type] == "array" && schema[:items].is_a?(Hash)
      validate_nesting_depth(schema[:items], errors, depth + 1)
    end
  end
end
