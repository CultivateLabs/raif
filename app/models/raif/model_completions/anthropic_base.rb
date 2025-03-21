# frozen_string_literal: true

class Raif::ModelCompletions::AnthropicBase < Raif::ModelCompletion
  def prompt_model_for_response!
    self.temperature ||= default_temperature

    # Build parameters for the specific API
    params = build_api_parameters

    # Make the API call and get the response
    resp = make_api_call(params)

    # Process the response based on format
    self.raw_response = if response_format_json?
      extract_json_response(resp)
    else
      extract_text_response(resp)
    end

    # Set token usage from response
    extract_token_usage(resp)

    save!
  end

protected

  def build_api_parameters
    raise NotImplementedError, "AnthropicBase subclasses must implement #build_api_parameters"
  end

  def make_api_call(params)
    raise NotImplementedError, "AnthropicBase subclasses must implement #make_api_call"
  end

  def extract_token_usage(resp)
    raise NotImplementedError, "AnthropicBase subclasses must implement #extract_token_usage"
  end

  def extract_text_response(resp)
    raise NotImplementedError, "AnthropicBase subclasses must implement #extract_text_response"
  end

  def extract_json_response(resp)
    raise NotImplementedError, "AnthropicBase subclasses must implement #extract_json_response"
  end

  # Common method for creating JSON tool structure.
  # Subclasses may need to format the tool differently.
  def create_json_tool
    tool_name = "json_response"

    schema = if source&.respond_to?(:json_response_schema)
      # Use the source's schema if available
      source.json_response_schema
    else
      default_json_response_schema
    end

    {
      name: tool_name,
      description: "Generate a structured JSON response based on the provided schema.",
      schema: schema
    }
  end
end
