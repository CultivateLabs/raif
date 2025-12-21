# frozen_string_literal: true

module Raif::Concerns::Llms::Google::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    tools = []
    function_declarations = []

    # If we support native tool use and have tools available, add them to the request
    if supports_native_tool_use? && model_completion.available_model_tools.any?
      model_completion.available_model_tools_map.each do |_tool_name, tool|
        if tool.provider_managed?
          # Provider-managed tools are added as separate tool entries
          tools << format_provider_managed_tool(tool)
        else
          function_declarations << {
            name: tool.tool_name,
            description: tool.tool_description,
            parameters: sanitize_schema_for_google(tool.tool_arguments_schema)
          }
        end
      end
    end

    # Add function declarations if any
    if function_declarations.any?
      tools << { functionDeclarations: function_declarations }
    end

    tools
  end

  def format_provider_managed_tool(tool)
    validate_provider_managed_tool_support!(tool)

    case tool.name
    when "Raif::ModelTools::ProviderManaged::WebSearch"
      { google_search: {} }
    when "Raif::ModelTools::ProviderManaged::CodeExecution"
      { code_execution: {} }
    else
      raise Raif::Errors::UnsupportedFeatureError,
        "Invalid provider-managed tool: #{tool.name} for #{key}"
    end
  end

  def build_forced_tool_choice(tool_name)
    { mode: "ANY", allowedFunctionNames: [tool_name] }
  end

private

  # Google's API doesn't support additionalProperties in JSON schemas
  # This method recursively removes it from the schema
  def sanitize_schema_for_google(schema)
    return schema unless schema.is_a?(Hash)

    sanitized = schema.except(:additionalProperties, "additionalProperties")

    sanitized.transform_values do |value|
      case value
      when Hash
        sanitize_schema_for_google(value)
      when Array
        value.map { |item| sanitize_schema_for_google(item) }
      else
        value
      end
    end
  end
end
