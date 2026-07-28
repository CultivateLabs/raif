# frozen_string_literal: true

module Raif::Concerns::Llms::Anthropic::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    tools = []

    # When the caller asks for a JSON response with a schema and the model can't
    # (or shouldn't) use native structured outputs, expose the schema as a
    # synthetic `json_response` tool. The model satisfies the request by calling
    # the tool with schema-matching arguments; `extract_json_response` unwraps
    # the tool-call input back into JSON.
    #
    # The native path (`use_native_structured_outputs?`) sends `output_config.format`
    # instead — enforced provider-side via constrained decoding, making this
    # synthetic tool redundant. That path is suppressed when the request
    # combines JSON output with provider-managed WebSearch, since Anthropic
    # documents structured outputs as incompatible with web-search citations
    # and we want to preserve citations on those requests.
    if model_completion.response_format_json? &&
        model_completion.json_response_schema.present? &&
        !use_native_structured_outputs?(model_completion)
      tools << json_response_tool_definition(model_completion)
    end

    # If we support native tool use and have tools available, add them to the request
    if supports_native_tool_use? && model_completion.available_model_tools.any?
      model_completion.available_model_tools_map.each do |_tool_name, tool|
        tools << if tool.provider_managed?
          format_provider_managed_tool(tool)
        else
          {
            name: tool.tool_name,
            description: tool.tool_description,
            input_schema: tool.tool_arguments_schema_for_source(model_completion.source)
          }
        end
      end
    end

    tools
  end

  # Without strict tool use the synthetic tool is advisory only, and models
  # occasionally emit stub or malformed inputs (empty objects, placeholder
  # values, payloads nested one level deep). strict: true makes the API
  # enforce the input schema via constrained decoding on models that support
  # it (gated on the same provider setting as native structured outputs,
  # which shipped together with strict tool use).
  def json_response_tool_definition(model_completion)
    tool = {
      name: "json_response",
      description: "Generate a structured JSON response based on the provided schema.",
      input_schema: model_completion.json_response_schema
    }

    if supports_structured_outputs?
      tool[:strict] = true
      tool[:input_schema] = Raif::Llms::Anthropic::StrictSchemaTransformer.call(tool[:input_schema])
    end

    tool
  end

  def format_provider_managed_tool(tool)
    validate_provider_managed_tool_support!(tool)

    case tool.name
    when "Raif::ModelTools::ProviderManaged::WebSearch"
      {
        type: "web_search_20250305",
        name: "web_search",
        max_uses: 5
      }
    when "Raif::ModelTools::ProviderManaged::CodeExecution"
      {
        type: "code_execution_20250522",
        name: "code_execution"
      }
    else
      raise Raif::Errors::UnsupportedFeatureError,
        "Invalid provider-managed tool: #{tool.name} for #{key}"
    end
  end

  def build_forced_tool_choice(tool_name)
    { "type" => "tool", "name" => tool_name, "disable_parallel_tool_use" => true }
  end

  def build_required_tool_choice(disable_parallel: true)
    { "type" => "any", "disable_parallel_tool_use" => disable_parallel }
  end
end
