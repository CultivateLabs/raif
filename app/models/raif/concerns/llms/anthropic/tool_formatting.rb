# frozen_string_literal: true

module Raif::Concerns::Llms::Anthropic::ToolFormatting
  extend ActiveSupport::Concern

  def build_tools_parameter(model_completion)
    tools = []

    # If we're looking for a JSON response, add a tool to the request that the model can use to provide a JSON response
    if model_completion.response_format_json? && model_completion.json_response_schema.present?
      tools << {
        name: "json_response",
        description: "Generate a structured JSON response based on the provided schema.",
        input_schema: model_completion.json_response_schema
      }
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
            input_schema: tool.tool_arguments_schema
          }
        end
      end
    end

    tools
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
end
