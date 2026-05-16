# frozen_string_literal: true

module Raif::Concerns::Llms::Bedrock::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    tools = []

    # When the caller asks for a JSON response with a schema and the model
    # doesn't support native structured outputs, expose the schema as a
    # synthetic `json_response` tool. The model satisfies the request by calling
    # the tool with schema-matching arguments; `extract_json_response` unwraps
    # the tool-call input back into JSON.
    #
    # The native path (`use_native_structured_outputs?`) sends
    # `output_config.text_format` instead — enforced provider-side via
    # constrained decoding, making this synthetic tool redundant.
    if model_completion.response_format_json? &&
        model_completion.json_response_schema.present? &&
        !use_native_structured_outputs?(model_completion)
      tools << {
        name: "json_response",
        description: "Generate a structured JSON response based on the provided schema.",
        input_schema: { json: model_completion.json_response_schema }
      }
    end

    model_completion.available_model_tools_map.each do |_tool_name, tool|
      tools << if tool.provider_managed?
        raise Raif::Errors::UnsupportedFeatureError,
          "Invalid provider-managed tool: #{tool.name} for #{key}"
      else
        {
          name: tool.tool_name,
          description: tool.tool_description,
          input_schema: { json: tool.tool_arguments_schema_for_source(model_completion.source) }
        }
      end
    end

    return {} if tools.blank?

    {
      tools: tools.map{|tool| { tool_spec: tool } }
    }
  end

  def build_forced_tool_choice(tool_name)
    { tool: { name: tool_name } }
  end

  def build_required_tool_choice
    { any: {} }
  end
end
